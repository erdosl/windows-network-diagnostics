#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent;. (Join-Path $root 'src\Core.ps1')
$cases=@(
    @{Exception=[UnauthorizedAccessException]::new('Zugriff verweigert');Status='PermissionDenied'},
    @{Exception=[ComponentModel.Win32Exception]::new(5,'Acceso denegado');Status='PermissionDenied'},
    @{Exception=[Exception]::new('access denied permission requires elevation');Status='Failed'},
    @{Exception=[ComponentModel.Win32Exception]::new(31,'Localized provider failure');Status='Failed'},
    @{Exception=[Exception]::new('Unknown');Status='Failed'})
foreach($case in $cases){$ex=$case.Exception;$r=Invoke-DiagnosticCheck 'Synthetic' {throw $ex};if($r.Status -ne $case.Status -or $r.Error.Message -ne $ex.Message){throw 'Structured error classification changed or message lost'}}
$category=[Management.Automation.ErrorRecord]::new([Exception]::new('Localized category'),'SyntheticDenied',[Management.Automation.ErrorCategory]::PermissionDenied,$null)
if((Invoke-DiagnosticCheck Synthetic {throw $category}).Status -ne 'PermissionDenied'){throw 'Structured category ignored'}
$ex=[Exception]::new('Localized missing object');$ex.Data['AdapterProviderContext']=$true;$ex.Data['AdapterProviderMissing']=$true
$r=Invoke-DiagnosticCheck Synthetic {throw $ex}
if($r.Status -ne 'Unavailable' -or $r.Error.ExceptionType -ne 'System.Exception'){throw 'Scoped missing provider record reinterpreted'}
$ex=[ComponentModel.Win32Exception]::new(31,'Provider failure');$ex.Data['AdapterProviderContext']=$true
$r=Invoke-DiagnosticCheck Synthetic {throw $ex}
if($r.Status -ne 'Failed' -or $r.Error.NativeErrorCode -ne 31){throw 'Scoped provider error 31 changed'}
Write-Host 'PASS: 8 structured/localized/unknown/provider error cases.'
