#requires -Version 5.1

<#
.SYNOPSIS
Verify the tool's schema-10 artifacts offline without rewriting them.
.DESCRIPTION
Uses a bounded worker (30 seconds default), at most 32 MiB per file and 128 MiB
total, and validates only safe sample basenames. Hashes establish integrity,
not authenticity. Exit 0 means Valid; exit 1 means invalid, incomplete,
unsupported, unavailable or timed out. No collection, probes or capture.
.EXAMPLE
powershell.exe -NoProfile -File .\Verify-NetworkDiagnostics.ps1 -Path '.\output\snapshot-example\evidence.json'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,120)][int]$TimeoutSeconds=30)
$ErrorActionPreference='Stop'
foreach($file in @('Core','State','Execution')){. (Join-Path $PSScriptRoot "src\$file.ps1")}
$resolved=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
$result=Invoke-BoundedCheck -Definition ([pscustomobject]@{Name='OfflineVerification';FunctionName='Test-DiagnosticArtifact';Arguments=@{Path=$resolved}}) -SourceDirectory (Join-Path $PSScriptRoot 'src') -WorkingDirectory ([IO.Path]::GetTempPath()) -TimeoutSeconds $TimeoutSeconds -AdditionalSources @((Join-Path $PSScriptRoot 'src\Verification.ps1'))
$result
if($result.Status -ne 'Success' -or @($result.Data).Count -ne 1 -or $result.Data[0].Status -ne 'Valid'){exit 1}
