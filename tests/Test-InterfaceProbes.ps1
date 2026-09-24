#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Connectivity.ps1')
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function Get-NetIPAddress {param($IPAddress,$ErrorAction);[pscustomobject]@{IPAddress=$IPAddress;InterfaceIndex=7}}
function Get-RoutePrediction {param($Destination);[pscustomobject]@{Attribution='RoutePrediction';Destination=$Destination}}
function Resolve-DnsName {throw 'Must not send DNS'}
function New-ProbeTcpClient {
    param($AddressFamily)
    $socket=[pscustomobject]@{Level=$null;Option=$null;OptionValue=$null;Endpoint=$null;LocalEndPoint=[Net.IPEndPoint]::new([Net.IPAddress]::Parse('192.0.2.10'),12345)}
    $socket|Add-Member ScriptMethod SetSocketOption {param($level,$option,$value);$this.Level=$level;$this.Option=$option;$this.OptionValue=$value}
    $socket|Add-Member ScriptMethod Bind {param($ep);$this.Endpoint=$ep}
    $client=[pscustomobject]@{Client=$socket;Closed=$false}
    $client|Add-Member ScriptMethod BeginConnect {param($a,$b,$c,$d);[pscustomobject]@{AsyncWaitHandle=[Threading.ManualResetEvent]::new($true)}}
    $client|Add-Member ScriptMethod EndConnect {param($r)}
    $client|Add-Member ScriptMethod Close {$this.Closed=$true}
    $script:lastClient=$client;$client
}
$dns=Invoke-ConnectivityProbe DNS '192.0.2.53' -RequestedInterfaceIndex 7 -RequestedSourceAddress '192.0.2.10'
Assert ($dns.Outcome -eq 'Unsupported' -and -not $dns.ObservedConnection) 'No falsely bound DNS'
$gateway=Invoke-ConnectivityProbe Gateway '192.0.2.1' -RequestedInterfaceIndex 7 -RequestedSourceAddress '192.0.2.10' -IncludeGatewayPing $true
Assert ($gateway.Outcome -eq 'Unsupported') 'No falsely bound ping'
$tcp=Invoke-ConnectivityProbe TCP '192.0.2.80' -RequestedInterfaceIndex 7 -RequestedSourceAddress '192.0.2.10'
Assert ($tcp.Outcome -eq 'Success' -and $tcp.ObservedConnection.LocalAddress -eq '192.0.2.10') 'Observed source retained'
Assert ($tcp.IntendedInterfaceIndex -eq 7 -and $tcp.RequestedSourceAddress -eq '192.0.2.10') 'Intended selection retained separately'
Assert ($tcp.ObservedConnection.InterfaceMatches[0].InterfaceIndex -eq 7 -and $tcp.RoutePrediction.Attribution -eq 'RoutePrediction') 'Prediction distinct from observed mapping'
Assert ($script:lastClient.Client.OptionValue -eq [Net.IPAddress]::HostToNetworkOrder(7)) 'IPv4 network byte order'
Assert ($script:lastClient.Closed) 'Socket disposed'
$v6=New-ProbeTcpClient InterNetworkV6
Set-ProbeInterfaceBinding $v6 7 '2001:db8::10' InterNetworkV6
Assert ($v6.Client.OptionValue -eq 7 -and $v6.Client.Level -eq 'IPv6') 'IPv6 host byte order'
$mismatch=Invoke-ConnectivityProbe TCP '2001:db8::80' -RequestedInterfaceIndex 7 -RequestedSourceAddress '192.0.2.10'
Assert ($mismatch.Outcome -eq 'Unsupported' -and -not $mismatch.ObservedConnection) 'Family mismatch no unbound fallback'
$missing=Invoke-ConnectivityProbe TCP '192.0.2.80' -RequestedInterfaceIndex 9 -RequestedSourceAddress '192.0.2.10'
Assert ($missing.Outcome -eq 'Unsupported') 'Wrong interface refused'
Write-Host "PASS: $script:count interface probe assertions; all socket and query operations mocked."
