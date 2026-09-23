#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\Connectivity.ps1')
$script:count = 0
function Assert-Probe { param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }; $script:count++
}
# Route/DNS/neighbour commands are mocked; sockets below use loopback only.
function Find-NetRoute {
    [CmdletBinding()] param([string]$RemoteIPAddress)
    [pscustomobject]@{ IPAddress = '192.0.2.123'; InterfaceIndex = 99; InterfaceAlias = 'Predicted only'; AddressFamily = 2 }
    [pscustomobject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '192.0.2.1'; InterfaceIndex = 99; RouteMetric = 1 }
}
function Get-NetIPAddress {
    [CmdletBinding()] param([string]$IPAddress)
    [pscustomobject]@{ IPAddress = $IPAddress; InterfaceIndex = 1; InterfaceAlias = 'Synthetic loopback'; AddressFamily = 2 }
}
function Get-NetNeighbor { [CmdletBinding()] param($InterfaceIndex,$IPAddress); throw 'Synthetic neighbour lookup failure' }
function Resolve-DnsName { [CmdletBinding()] param($Name,$Type,$Server,[switch]$DnsOnly,[switch]$NoHostsFile,[switch]$QuickTimeout); throw 'Synthetic DNS refusal' }
$gateway = Invoke-ConnectivityProbe -Kind Gateway -Destination '192.0.2.1' -InterfaceIndex 7
Assert-Probe ($gateway.Outcome -eq 'Failed' -and $gateway.Evidence.NeighbourError -match 'Synthetic' -and $null -eq $gateway.Evidence.ICMP) 'Gateway neighbour failure recorded without a ping by default'
Assert-Probe ($null -eq $gateway.ObservedConnection -and $gateway.RoutePrediction.Attribution -eq 'RoutePrediction') 'Gateway configuration does not claim observed path'
$dns = Invoke-ConnectivityProbe -Kind DNS -Destination '192.0.2.53' -QueryName 'synthetic.invalid' -QueryType AAAA
Assert-Probe ($dns.Outcome -eq 'Failed' -and $dns.Evidence.QueryType -eq 'AAAA' -and $dns.Error.Message -match 'Synthetic') 'DNS failure preserves query and error'
Assert-Probe ($dns.AddressFamily -eq 'InterNetwork') 'DNS server transport family distinct from AAAA query type'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$tcp = Invoke-ConnectivityProbe -Kind TCP -Destination '127.0.0.1' -Port $port -TimeoutMs 200
Assert-Probe ($tcp.Outcome -in @('Failed','TimedOut') -and $null -eq $tcp.ObservedConnection -and $tcp.Error) 'Closed loopback TCP records failure or timeout, not a fabricated path'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
try {
    # The local listener deliberately sends no TLS response. No external service is contacted.
    $https = Invoke-ConnectivityProbe -Kind HTTPS -Destination '127.0.0.1' -Port $listener.LocalEndpoint.Port -Endpoint 'https://localhost/' -TimeoutMs 200
} finally { $listener.Stop() }
Assert-Probe ($https.Outcome -eq 'TimedOut' -and $https.Error.Message -match 'TLS') "HTTPS TLS timeout retained (actual outcome: $($https.Outcome); error: $($https.Error.Message))"
Assert-Probe ($https.ObservedConnection.LocalAddress -eq '127.0.0.1' -and $https.ObservedConnection.InterfaceMatches[0].InterfaceIndex -eq 1) 'Actual socket endpoint retained even when TLS fails'
Assert-Probe ($https.RoutePrediction.SourceAddresses[0].InterfaceIndex -eq 99) 'Route prediction remains separate from observed connection'
foreach ($probe in @($gateway,$dns,$tcp,$https)) {
    Assert-Probe ($probe.StartedAt -match '[+-]\d\d:\d\d$' -and $probe.CompletedAt -and $probe.DurationMs -ge 0) 'Probe timing recorded'
}
$checks = @($gateway,$dns,$tcp,$https | ForEach-Object { [pscustomobject]@{ Name = ('Connectivity:' + $_.Kind); Status = 'Success'; Data = @($_) } })
Assert-Probe ((Get-DiagnosticFindings $checks).Hypotheses.Count -eq 0) 'Probe failures alone produce no diagnosis'
Write-Host "PASS: $script:count probe assertions; mocked commands and loopback-only sockets."
