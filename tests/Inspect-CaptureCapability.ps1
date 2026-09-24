#requires -Version 5.1
# Read-only local tool help/export availability, never initializes capture.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Capture.ps1')
Get-NativeCaptureCapability | Format-List
