#requires -Version 5.1
param([Parameter(Mandatory)][string]$InputPath, [Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
try {
    $request = Import-Clixml -LiteralPath $InputPath
    foreach ($source in $request.SourcePaths) { . $source }
    $arguments = $request.Arguments
    $result = Invoke-DiagnosticCheck -Name $request.Name -Action { & $request.FunctionName @arguments }
    # Serialize before crossing the process boundary. CLIXML-enriched enum values
    # can acquire duplicate value/Value JSON keys when reserialized by the parent.
    [IO.File]::WriteAllText($ResultPath, (ConvertTo-Json -InputObject $result -Depth 24), [Text.UTF8Encoding]::new($false))
} catch {
    # A bootstrap failure is evidence too, including blocked dot-sourcing.
    $failure = [pscustomobject]@{ Name = 'WorkerBootstrap'; Status = 'Failed'; Data = @(); Error = [pscustomobject]@{
        Message = $_.Exception.Message; Id = $_.FullyQualifiedErrorId; Category = [string]$_.CategoryInfo.Category
    } }
    [IO.File]::WriteAllText($ResultPath, (ConvertTo-Json -InputObject $failure -Depth 8), [Text.UTF8Encoding]::new($false))
    exit 1
}
