# Synthetic worker fixture: expires during route setup, before any socket operation.
function Invoke-ReviewDeadlineProbe {
    function Get-RoutePrediction { param($Destination); Start-Sleep -Milliseconds 250; [pscustomobject]@{ Attribution = 'Synthetic' } }
    Invoke-ConnectivityProbe -Kind TCP -Destination '192.0.2.1' -TimeoutMs 100
}
function Invoke-ReviewStalledProbe { Start-Sleep -Seconds 30 }
