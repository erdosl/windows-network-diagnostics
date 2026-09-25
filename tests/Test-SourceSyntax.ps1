#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$files=@(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File)
foreach($dir in @('src','tests','examples')){$files+=@(Get-ChildItem -LiteralPath (Join-Path $root $dir) -Filter '*.ps1' -Recurse -File)}
foreach($file in $files){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors | Out-String)}}
Write-Host "PASS: $($files.Count) PowerShell files parsed in Windows PowerShell $($PSVersionTable.PSVersion). Parsing does not replace execution."
