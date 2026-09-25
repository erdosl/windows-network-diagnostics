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
    param($Root,$Node,[string]$RunId,[int]$Depth=0,[string]$Location='')
    if($Depth -gt 48){throw 'Reference traversal depth limit exceeded.'}
    if($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]){return}
    if($Node -is [array]){for($i=0;$i -lt $Node.Count;$i++){Test-ArtifactReferences $Root $Node[$i] $RunId ($Depth+1) "$Location/$i"};return}
    if($Node.PSObject.Properties['Scope']){
        if($Node.Scope -notin @('Current','Baseline','Observation')){"$Location/Scope: expected Current, Baseline or Observation."}
        $expected=$RunId;if($Node.Scope -eq 'Baseline'){$expected=$Root.ContextEvidence.Baseline.Identity.RunId}
        if(-not $Node.RunId -or $Node.RunId -ne $expected){"$Location/RunId: scoped identity mismatch."}
        if($Node.Scope -eq 'Observation' -and -not $Node.Artifact){"$Location/Artifact: observation scope requires a sample artifact."}
        foreach($pointer in @($Node.Path)+@($Node.EvidenceReferences)+@($Node.CheckReferences)){
            if($pointer -is [string] -and (($Node.Scope -eq 'Baseline' -and -not $pointer.StartsWith('/ContextEvidence/Baseline')) -or ($Node.Scope -eq 'Current' -and $pointer.StartsWith('/ContextEvidence/Baseline')))){"$Location : pointer $pointer conflicts with scope."}
        }
    }
    foreach($property in $Node.PSObject.Properties){
        $name=$property.Name;$at="$Location/$name"
        # Explicit artifact reference-bearing families. Never search arbitrary
        # provider payloads or user-supplied values for reference-like strings.
        if($Location -eq '' -and $name -notin @('Findings','ConfigurationOrigins','VpnInterfaceContext','LogicalNetwork','DhcpSummary','SnapshotComparison','ExpectationAssessment','HistoricalEventContext','ContextEvidence','ContextInputs','Changes','CounterDeltas','StatisticsCoverage','Samples','Metadata','Checks','EventCoverage')){continue}
        if($name -in @('Error','Errors','Values','Before','After','Records','Raw','Xml','Message','EffectiveExpectations','IncidentContext','AdapterEvidence','IPInterfaceEvidence','LeaseRaw')){continue}
        if($name -eq 'Data' -and $at -notmatch '^/ContextInputs/\d+/Data$'){continue}
        if($at -match '/Checks/\d+/Data$' -or $at -match '/ContextInputs/\d+/Data$' -and $Node.Name -ne 'Baseline'){continue}
        if($name -in @('EvidenceReferences','CheckReferences','RouteReferences')){
            if($property.Value -isnot [array]){"${at}: expected pointer array."}
            foreach($pointer in $property.Value){if($pointer -isnot [string] -or -not (Test-EvidencePointer $Root $pointer)){"${at}: missing reference $pointer"}}
        }
        if($name -in @('Path','EvidencePath','EvidenceReference','ChecksPath','WindowsCheckPath','Reference') -and $null -ne $property.Value -and $property.Value -isnot [string] -and $property.Value -isnot [pscustomobject]){"${at}: expected pointer string or scoped reference object."}
        if($name -in @('Path','EvidencePath','EvidenceReference','ChecksPath','WindowsCheckPath','Reference') -and $property.Value -is [string] -and -not ($Location -match '^/Samples/\d+$' -and $name -eq 'Path')){
            # Observation Before/AfterArtifact references are resolved by the caller.
            if(-not $Node.Artifact -and -not (Test-EvidencePointer $Root $property.Value)){"${at}: missing reference $($property.Value)"}
        }
        Test-ArtifactReferences $Root $property.Value $RunId ($Depth+1) $at
    }
}

function Test-ObservationReferences {
    param($Node,$Samples,[int]$Depth=0,[string]$Location='')
    if($Depth -gt 48){throw 'Observation reference depth limit exceeded.'}
    if($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]){return}
    if($Node -is [array]){for($i=0;$i -lt $Node.Count;$i++){Test-ObservationReferences $Node[$i] $Samples ($Depth+1) "$Location/$i"};return}
    foreach($side in @('Before','After')){
        $artifact=$Node.($side+'Artifact');$pointer=$Node.($side+'Path')
        if($artifact){if(-not $Samples.ContainsKey($artifact) -or ($pointer -and -not (Test-EvidencePointer $Samples[$artifact] $pointer))){"$Location/$side : unresolved observation field/artifact reference."}}
        elseif($pointer){"$Location/$side : pointer requires artifact."}
    }
    if($Node.Artifact){
        if(-not $Samples.ContainsKey([string]$Node.Artifact)){"$Location/Artifact: unresolved sample $($Node.Artifact)."}
        elseif($Node.Path -and -not (Test-EvidencePointer $Samples[[string]$Node.Artifact] $Node.Path)){"$Location/Path: unresolved pointer $($Node.Path) in $($Node.Artifact)."}
        elseif($Node.EvidencePath -and -not (Test-EvidencePointer $Samples[[string]$Node.Artifact] $Node.EvidencePath)){"$Location/EvidencePath: unresolved pointer in $($Node.Artifact)."}
        elseif($Node.SourceCheck -and -not @($Samples[[string]$Node.Artifact].Checks | Where-Object Name -eq $Node.SourceCheck).Count){"$Location/SourceCheck: expected named check in $($Node.Artifact)."}
    }
    foreach($p in $Node.PSObject.Properties){
        if($Location -eq '' -and $p.Name -notin @('Samples','Changes','CounterDeltas','StatisticsCoverage','EventCoverage')){continue}
        if($p.Name -in @('Values','Before','After','Records','Data')){continue}
        Test-ObservationReferences $p.Value $Samples ($Depth+1) ($Location+'/'+$p.Name)
    }
}

function Test-ArtifactStructure {
    param($Node,[string]$Kind,[string]$Artifact)
    function Issue($Field,$Expected){"$Artifact/$Field : expected $Expected."}
    if($Node -isnot [pscustomobject]){Issue '' 'artifact object';return}
    if($Node.SchemaVersion -isnot [int] -and $Node.SchemaVersion -isnot [long]){Issue SchemaVersion 'integer'}
    if($Node.Revision -isnot [int] -and $Node.Revision -isnot [long]){Issue Revision 'nonnegative integer'}
    elseif($Node.Revision -lt 0){Issue Revision 'nonnegative integer'}
    $start=$Node.StartedAt;if($Kind -eq 'Observation'){$start=$Node.Identity.StartedAt}
    if(-not (ConvertTo-ContextTime $start)){Issue StartedAt 'valid offset timestamp'}
    if($Node.CollectionStatus -isnot [string] -or $Node.CollectionStatus -notin @('Complete','Incomplete','Interrupted')){Issue CollectionStatus 'legal collection state string'}
    if($Node.CollectionStatus -eq 'Complete' -and -not (ConvertTo-ContextTime $Node.CompletedAt)){Issue CompletedAt 'valid completion timestamp for Complete collection'}
    if($Node.Analysis.Status -notin @('Pending','Complete','Partial')){Issue 'Analysis/Status' 'Pending, Complete or Partial'}
    if($Node.Analysis.ContractVersion -ne 1 -or $Node.Analysis.EvidenceRevision -ne $Node.Revision){Issue Analysis 'contract 1 with matching evidence revision'}
    if($Node.Analysis.Sections){
        if($Node.Analysis.Sections -isnot [array]){Issue 'Analysis/Sections' 'array'}
        foreach($section in $Node.Analysis.Sections){
            if($section.Status -notin @('Complete','Failed') -or $section.EvidenceRevision -ne $Node.Revision){Issue 'Analysis/Sections' 'legal section status and matching revision'}
            if($section.Status -eq 'Failed' -and ($Node.Analysis.Status -eq 'Complete' -or -not $section.Error)){Issue 'Analysis/Sections' 'failed section error and limited analysis coverage'}
        }
    }
    if($Kind -ne 'Sample'){
        if($Node.Publication.Canonical -notin @('Pending','Published','Failed') -or $Node.Publication.Html -notin @('Pending','Published','Failed','Rendering')){Issue Publication 'legal canonical and HTML states'}
        if($Node.Metadata.CollectorVersion -isnot [string] -or -not $Node.Metadata.CollectorVersion){Issue 'Metadata/CollectorVersion' 'version string'}
        if($Node.Metadata.Runtime.Version -isnot [string] -or -not $Node.Metadata.OS.Provenance){Issue Metadata 'attributed runtime and OS metadata'}
        if($Node.Metadata.Contracts.Context -ne 4 -or $Node.Metadata.Contracts.ObservationComparison -ne 5){Issue 'Metadata/Contracts' 'context 4 and observation comparison 5'}
        if($Kind -eq 'Snapshot' -and $Node.Publication.Html -eq 'Published' -and $Node.Publication.HtmlEvidenceRevision -ne $Node.Revision){Issue 'Publication/HtmlEvidenceRevision' 'matching rendered revision'}
    }elseif($Node.Timing.ContractVersion -ne 2){Issue 'Timing/ContractVersion' 'sample collection timing contract 2'}
    if($Kind -eq 'Observation'){
        if($Node.Identity.ComputerName -isnot [string] -or -not $Node.Identity.ComputerName){Issue 'Identity/ComputerName' 'computer identity'}
        if($Node.Timing.ContractVersion -ne 1){Issue 'Timing/ContractVersion' 'run timing contract 1'}
        if($Node.CollectionStatus -eq 'Complete' -and ($null -eq $Node.Timing.CollectionElapsedSeconds -or $Node.Timing.CollectionElapsedSeconds -lt 0)){Issue 'Timing/CollectionElapsedSeconds' 'nonnegative completed collection interval'}
    }elseif($Kind -eq 'Snapshot'){
        if($Node.ComputerName -isnot [string] -or -not $Node.ComputerName){Issue ComputerName 'computer identity'}
    }
    if($Kind -ne 'Observation'){
        if($Node.Checks -isnot [array]){Issue Checks 'check array'}
        for($i=0;$i -lt @($Node.Checks).Count;$i++){
            $check=$Node.Checks[$i]
            if($check.Name -isnot [string] -or -not $check.Name -or $check.Status -notin @('Success','Failed','Unavailable','PermissionDenied','TimedOut','Interrupted','Skipped')){Issue "Checks/$i" 'named check with legal status'}
            if($check.Data -isnot [array]){Issue "Checks/$i/Data" 'array'}
        }
        if($Node.ContextEvidence){
            $identity=$Node.ContextEvidence.Current.Identity
            foreach($field in @('RunId','StartedAt','CompletedAt','CollectionStatus')){if($identity.$field -ne $Node.$field){Issue "ContextEvidence/Current/Identity/$field" 'identity consistent with artifact'}}
        }
    }
}

function Test-DiagnosticArtifact {
    param([string]$Path)
    if($Path.StartsWith('\\') -or $Path -match '^[a-z]+://' -or $Path.Substring([Math]::Min(2,$Path.Length)).Contains(':')){throw 'Offline verification requires a local filesystem path without alternate streams.'}
    $root=Read-VerificationJson $Path
    $issues=@();$samples=@{};$bytes=(Get-Item -LiteralPath $Path).Length
    if($root.SchemaVersion -ne 11){return [pscustomobject]@{Status='Unsupported';Issues=@('Verifier supports schema 11 only; older contracts are not silently accepted.');Integrity='Not assessed';Authenticity='Not assessed'}}
    $run=$root.RunId;if($root.Mode -eq 'Observation'){$run=$root.Identity.RunId}
    $structural=@(Test-ArtifactStructure $root $root.Mode 'evidence.json');$references=@();$hashIssues=@()
    $guid=[guid]::Empty
    if(-not [guid]::TryParse([string]$run,[ref]$guid) -or $guid -eq [guid]::Empty){$issues+='Missing or invalid run identity.'}
    if($root.CollectionStatus -notin @('Complete','Incomplete','Interrupted')){$issues+='Invalid collection status.'}
    if($root.Metadata.ContractVersion -ne 1 -or $root.Metadata.RunId -ne $run -or $root.Metadata.Mode -ne $root.Mode -or $root.Metadata.Contracts.Schema -ne 11){$issues+='Metadata identity/contract mismatch.'}
    if($root.Analysis.ContractVersion -ne 1 -or $root.Publication.ContractVersion -ne 1){$issues+='Unsupported analysis/publication contract.'}
    if($root.Analysis.EvidenceRevision -ne $root.Revision -or $root.Publication.EvidenceRevision -ne $root.Revision){$issues+='Analysis/publication evidence revision mismatch.'}
    if($null -eq $root.Revision -or $root.Revision -isnot [ValueType] -or $root.Revision -lt 0){$issues+='Missing or invalid evidence revision.'}
    if($root.Mode -eq 'Snapshot'){
        if($root.Checks -isnot [array]){$issues+='Checks must be an array.'}
        if($root.ContextEvidence -and $root.ContextEvidence.ContractVersion -ne 4){$issues+='Unsupported context contract.'}
    }elseif($root.Mode -eq 'Observation'){
        if($root.ObservationComparisonVersion -ne 5){$issues+='Unsupported observation comparison contract.'}
        if($root.Samples -isnot [array] -or $root.Samples.Count -gt 121){throw 'Invalid or excessive sample list.'}
        $directory=Split-Path -Parent ([IO.Path]::GetFullPath($Path));$sequence=0
        foreach($reference in $root.Samples){
            $expected='sample-{0:D4}.json' -f $sequence
            if($reference.Path -cne $expected -or $reference.Sequence -ne $sequence){throw 'Unsafe path or invalid sample sequence.'}
            $samplePath=Join-Path $directory $expected
            if(-not [IO.File]::Exists($samplePath)){$issues+="$expected : missing sample.";$hashIssues+="$expected/Sha256: sample unavailable for hashing.";$sequence++;continue}
            $bytes+=(Get-Item -LiteralPath $samplePath).Length
            if($bytes -gt 134217728){throw 'Total artifact byte budget exceeded.'}
            $sample=Read-VerificationJson $samplePath
            $structural+=@(Test-ArtifactStructure $sample Sample $expected)
            if($sample.RunId -ne $run -or $sample.Sequence -ne $sequence -or $sample.SchemaVersion -ne 11 -or $sample.ObservationComparisonVersion -ne 5 -or $sample.Checks -isnot [array]){$issues+='Sample identity/structure mismatch.'}
            if($sample.Analysis.ContractVersion -ne 1 -or $null -eq $sample.Revision -or $sample.Analysis.EvidenceRevision -ne $sample.Revision){$issues+='Sample analysis contract/revision mismatch.'}
            if($sample.CollectionStatus -ne $reference.Status){$issues+='Sample status mismatch.'}
            if(-not $reference.Sha256){$hashIssues+="$expected/Sha256: sample hash unavailable."}
            elseif((Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash -ne $reference.Sha256){$hashIssues+="$expected/Sha256: sample hash mismatch."}
            $references+=@(Test-ArtifactReferences $sample $sample $run | ForEach-Object {"$expected : $_"})
            $samples[$expected]=$sample;$sequence++
        }
        $references+=@(Test-ObservationReferences $root $samples)
        foreach($sample in $samples.Values){$references+=@(Test-ObservationReferences $sample $samples)}
    }else{$issues+='Unsupported artifact mode.'}
    $references+=@(Test-ArtifactReferences $root $root $run)
    $structural+=@($issues | ForEach-Object {"evidence.json : $_"});$issues=$structural+$references+$hashIssues
    [pscustomobject]@{Status=$(if($issues.Count){'Invalid'}elseif($root.CollectionStatus -ne 'Complete'){'Incomplete'}else{'Valid'});Mode=$root.Mode;CollectionStatus=$root.CollectionStatus;AnalysisCoverage=$root.Analysis.Status;Structure=$(if($structural.Count){'Invalid'}else{'Valid'});References=$(if($references.Count){'Invalid'}else{'Valid'});SampleHashes=$(if($root.Mode -ne 'Observation'){'Not applicable'}elseif($hashIssues.Count){'Invalid'}else{'Valid'});Issues=$issues;SamplesChecked=$samples.Count;Integrity='Structural/reference/hash checks only';Authenticity='Not assessed: matching hashes do not establish who produced an artifact.'}
}
