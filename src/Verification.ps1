function Read-VerificationJson {
    param([string]$Path,[long]$MaxBytes=33554432)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Expected a regular artifact file, not a reparse point.'}
    if($file.Length -gt $MaxBytes){throw 'Artifact exceeds verification byte limit.'}
    Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Test-EvidencePointer {
    param($Root,[string]$Pointer)
    if(-not $Pointer.StartsWith('/')){return $false}
    $node=$Root
    foreach($part in $Pointer.Substring(1).Split('/')){
        $key=$part.Replace('~1','/').Replace('~0','~')
        if($null -eq $node){return $false}
        if($node -is [array]){
            $index=0;if(-not [int]::TryParse($key,[ref]$index) -or $index -lt 0 -or $index -ge $node.Count){return $false};$node=$node[$index]
        }else{
            $property=$node.PSObject.Properties[$key];if(-not $property){return $false};$node=$property.Value
        }
    }
    $true
}

function Test-ArtifactReferences {
    param($Root,$Node,[string]$RunId,[int]$Depth=0)
    if($Depth -gt 48){throw 'Reference traversal depth limit exceeded.'}
    if($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]){return}
    if($Node -is [array]){foreach($item in $Node){Test-ArtifactReferences $Root $item $RunId ($Depth+1)};return}
    foreach($property in $Node.PSObject.Properties){
        if($property.Name -in @('EvidenceReferences','CheckReferences')){
            foreach($pointer in $property.Value){if($pointer -is [string] -and $pointer.StartsWith('/') -and -not (Test-EvidencePointer $Root $pointer)){"Missing reference: $pointer"}}
        }
        if($property.Name -in @('Path','EvidencePath','EvidenceReference','ChecksPath','WindowsCheckPath') -and $property.Value -is [string] -and $property.Value.StartsWith('/')){
            # Observation Before/AfterArtifact references are resolved by the caller.
            if(-not $Node.Artifact -and -not (Test-EvidencePointer $Root $property.Value)){"Missing reference: $($property.Value)"}
            if($Node.Scope -and $Node.RunId){
                if($Node.Scope -notin @('Current','Baseline','Observation')){'Unsupported reference scope.'}
                $expected=$RunId;if($Node.Scope -eq 'Baseline'){$expected=$Root.ContextEvidence.Baseline.Identity.RunId}
                if($Node.RunId -ne $expected){'Scoped reference run identity mismatch.'}
            }
        }
        Test-ArtifactReferences $Root $property.Value $RunId ($Depth+1)
    }
}

function Test-ObservationReferences {
    param($Node,$Samples,[int]$Depth=0)
    if($Depth -gt 48){throw 'Observation reference depth limit exceeded.'}
    if($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]){return}
    if($Node -is [array]){foreach($item in $Node){Test-ObservationReferences $item $Samples ($Depth+1)};return}
    foreach($side in @('Before','After')){
        $artifact=$Node.($side+'Artifact');$pointer=$Node.($side+'Path')
        if($artifact -and $pointer){if(-not $Samples.ContainsKey($artifact) -or -not (Test-EvidencePointer $Samples[$artifact] $pointer)){'Unresolved observation field reference.'}}
    }
    if($Node.Artifact){
        if(-not $Samples.ContainsKey([string]$Node.Artifact)){'Unresolved observation artifact reference.'}
        elseif($Node.Path -and -not (Test-EvidencePointer $Samples[[string]$Node.Artifact] $Node.Path)){'Unresolved observation record reference.'}
        elseif($Node.EvidencePath -and -not (Test-EvidencePointer $Samples[[string]$Node.Artifact] $Node.EvidencePath)){'Unresolved observation evidence reference.'}
        elseif($Node.SourceCheck -and -not @($Samples[[string]$Node.Artifact].Checks | Where-Object Name -eq $Node.SourceCheck).Count){'Unresolved observation source check.'}
    }
    foreach($p in $Node.PSObject.Properties){Test-ObservationReferences $p.Value $Samples ($Depth+1)}
}

function Test-DiagnosticArtifact {
    param([string]$Path)
    if($Path.StartsWith('\\') -or $Path -match '^[a-z]+://' -or $Path.Substring([Math]::Min(2,$Path.Length)).Contains(':')){throw 'Offline verification requires a local filesystem path without alternate streams.'}
    $root=Read-VerificationJson $Path
    $issues=@();$samples=@{};$bytes=(Get-Item -LiteralPath $Path).Length
    if($root.SchemaVersion -ne 10){return [pscustomobject]@{Status='Unsupported';Issues=@('Verifier supports schema 10 only; older contracts are not silently accepted.');Integrity='Not assessed';Authenticity='Not assessed'}}
    $run=$root.RunId;if($root.Mode -eq 'Observation'){$run=$root.Identity.RunId}
    $guid=[guid]::Empty
    if(-not [guid]::TryParse([string]$run,[ref]$guid) -or $guid -eq [guid]::Empty){$issues+='Missing or invalid run identity.'}
    if($root.CollectionStatus -notin @('Complete','Incomplete','Interrupted')){$issues+='Invalid collection status.'}
    if($root.Metadata.ContractVersion -ne 1 -or $root.Metadata.RunId -ne $run -or $root.Metadata.Mode -ne $root.Mode -or $root.Metadata.Contracts.Schema -ne 10){$issues+='Metadata identity/contract mismatch.'}
    if($root.Analysis.ContractVersion -ne 1 -or $root.Publication.ContractVersion -ne 1){$issues+='Unsupported analysis/publication contract.'}
    if($root.Analysis.EvidenceRevision -ne $root.Revision -or $root.Publication.EvidenceRevision -ne $root.Revision){$issues+='Analysis/publication evidence revision mismatch.'}
    if($null -eq $root.Revision -or $root.Revision -isnot [ValueType] -or $root.Revision -lt 0){$issues+='Missing or invalid evidence revision.'}
    if($root.Mode -eq 'Snapshot'){
        if($root.Checks -isnot [array]){$issues+='Checks must be an array.'}
        if($root.ContextEvidence -and $root.ContextEvidence.ContractVersion -ne 4){$issues+='Unsupported context contract.'}
    }elseif($root.Mode -eq 'Observation'){
        if($root.ObservationComparisonVersion -ne 4){$issues+='Unsupported observation comparison contract.'}
        if($root.Samples -isnot [array] -or $root.Samples.Count -gt 121){throw 'Invalid or excessive sample list.'}
        $directory=Split-Path -Parent ([IO.Path]::GetFullPath($Path));$sequence=0
        foreach($reference in $root.Samples){
            $expected='sample-{0:D4}.json' -f $sequence
            if($reference.Path -cne $expected -or $reference.Sequence -ne $sequence){throw 'Unsafe path or invalid sample sequence.'}
            $samplePath=Join-Path $directory $expected
            if(-not [IO.File]::Exists($samplePath)){$issues+='Missing sample.';$sequence++;continue}
            $bytes+=(Get-Item -LiteralPath $samplePath).Length
            if($bytes -gt 134217728){throw 'Total artifact byte budget exceeded.'}
            $sample=Read-VerificationJson $samplePath
            if($sample.RunId -ne $run -or $sample.Sequence -ne $sequence -or $sample.SchemaVersion -ne 10 -or $sample.ObservationComparisonVersion -ne 4 -or $sample.Checks -isnot [array]){$issues+='Sample identity/structure mismatch.'}
            if($sample.Analysis.ContractVersion -ne 1 -or $null -eq $sample.Revision -or $sample.Analysis.EvidenceRevision -ne $sample.Revision){$issues+='Sample analysis contract/revision mismatch.'}
            if($sample.CollectionStatus -ne $reference.Status){$issues+='Sample status mismatch.'}
            if(-not $reference.Sha256){$issues+='Sample hash unavailable.'}
            elseif((Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash -ne $reference.Sha256){$issues+='Sample hash mismatch.'}
            $issues+=@(Test-ArtifactReferences $sample $sample $run)
            $samples[$expected]=$sample;$sequence++
        }
        $issues+=@(Test-ObservationReferences $root $samples)
        foreach($sample in $samples.Values){$issues+=@(Test-ObservationReferences $sample $samples)}
    }else{$issues+='Unsupported artifact mode.'}
    $issues+=@(Test-ArtifactReferences $root $root $run)
    [pscustomobject]@{Status=$(if($issues.Count){'Invalid'}elseif($root.CollectionStatus -ne 'Complete'){'Incomplete'}else{'Valid'});Mode=$root.Mode;CollectionStatus=$root.CollectionStatus;Issues=$issues;SamplesChecked=$samples.Count;Integrity='Structural/reference/hash checks only';Authenticity='Not assessed: matching hashes do not establish who produced an artifact.'}
}
