#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
foreach($file in @('Core','State','Verification')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
$id=New-SnapshotIdentity
$e=[pscustomobject]@{SchemaVersion=10;Mode='Snapshot';RunId=$id.RunId;Metadata=(Get-RunMetadata $id Snapshot);CollectionStatus='Complete';Revision=1;Checks=@();ContextInputs=@();StartedAt=$id.StartedAt}
# Fixture construction is ordinary test-file I/O, not a persistence validation.
function Write-CanonicalEvidence {param($Evidence,$Path);[IO.File]::WriteAllText($Path,(ConvertTo-Json $Evidence -Depth 32))}
$e | Add-Member NoteProperty Analysis ([pscustomobject]@{ContractVersion=1;Status='Complete';EvidenceRevision=1})
$e | Add-Member NoteProperty Publication ([pscustomobject]@{ContractVersion=1;Canonical='Published';EvidenceRevision=1})
$paths=[pscustomobject]@{JsonPath=(Join-Path $work 'evidence.json')}
Write-CanonicalEvidence $e $paths.JsonPath
if((Test-DiagnosticArtifact $paths.JsonPath).Status -ne 'Valid'){throw 'Valid snapshot rejected'}
$beforeHash=(Get-FileHash -LiteralPath $paths.JsonPath).Hash
$null=& powershell.exe -NoProfile -File (Join-Path $root 'Verify-NetworkDiagnostics.ps1') -Path $paths.JsonPath
if($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $paths.JsonPath).Hash -ne $beforeHash){throw 'Bounded verifier exit or read-only contract failed'}
$e | Add-Member NoteProperty BadReference ([pscustomobject]@{Scope='Current';RunId=$id.RunId;Path='/Checks/99'})
Write-CanonicalEvidence $e $paths.JsonPath
if((Test-DiagnosticArtifact $paths.JsonPath).Status -ne 'Invalid'){throw 'Missing reference accepted'}
$ErrorActionPreference='Continue';$null=& powershell.exe -NoProfile -File (Join-Path $root 'Verify-NetworkDiagnostics.ps1') -Path $paths.JsonPath 2>&1;$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
if($code -eq 0){throw 'Invalid artifact command returned success'}
$sample=[pscustomobject]@{SchemaVersion=10;ObservationComparisonVersion=4;RunId=$id.RunId;Sequence=0;CollectionStatus='Complete';Checks=@([pscustomobject]@{Name='ObservationStatistics';Status='Success';Data=@()});StatisticsCoverage=@{ContractVersion=1;EvidencePath='/Checks/0'}}
$sample | Add-Member NoteProperty Revision 1
$sample | Add-Member NoteProperty Analysis ([pscustomobject]@{ContractVersion=1;EvidenceRevision=1})
$samplePath=Join-Path $work 'sample-0000.json';Write-CanonicalEvidence $sample $samplePath
$manifest=[pscustomobject]@{SchemaVersion=10;ObservationComparisonVersion=4;Mode='Observation';Identity=$id;Metadata=(Get-RunMetadata $id Observation);Revision=1;CollectionStatus='Complete';Analysis=@{ContractVersion=1;EvidenceRevision=1};Publication=@{ContractVersion=1;EvidenceRevision=1};Samples=@([pscustomobject]@{Path='sample-0000.json';Sequence=0;Status='Complete';Sha256=(Get-FileHash -LiteralPath $samplePath).Hash})}
$manifest.Samples[0] | Add-Member NoteProperty StatisticsCoverage ([pscustomobject]@{ContractVersion=1;Artifact='sample-0000.json';EvidencePath='/Checks/0'})
Write-CanonicalEvidence $manifest $paths.JsonPath
if((Test-DiagnosticArtifact $paths.JsonPath).Status -ne 'Valid'){throw 'Valid observation rejected'}
$manifest.Samples[0].Sha256='bad';Write-CanonicalEvidence $manifest $paths.JsonPath
if((Test-DiagnosticArtifact $paths.JsonPath).Issues -notcontains 'Sample hash mismatch.'){throw 'Hash mismatch not detected'}
$manifest.Samples[0].Path='..\outside.json';Write-CanonicalEvidence $manifest $paths.JsonPath
$rejected=$false;try{Test-DiagnosticArtifact $paths.JsonPath}catch{$rejected=$true};if(-not $rejected){throw 'Unsafe referenced path accepted'}
$manifest.SchemaVersion=9;Write-CanonicalEvidence $manifest $paths.JsonPath
if((Test-DiagnosticArtifact $paths.JsonPath).Status -ne 'Unsupported'){throw 'Older contract silently accepted'}
Write-Host 'PASS: synthetic artifact verification, real bounded command exits/read-only hashes, reference resolution, sample identity, hash and path rejection, explicit older-contract result. Fixture writes do not validate atomic replacement.'
