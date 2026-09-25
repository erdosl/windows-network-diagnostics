#requires -Version 5.1
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
Import-Module Microsoft.PowerShell.Utility
foreach($file in @('Core','State','Events','Observation')){. (Join-Path $root "src\$file.ps1")}
. (Join-Path $PSScriptRoot 'TestWorkRoot.ps1');$work=New-TestWorkRoot
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$script:files=@{};$script:raw=@()
function Set-AtomicText {param($Path,$Text);$script:files[$Path]=$Text;if($Path -match 'sample-\d+.json$'){$script:raw+=($Text|ConvertFrom-Json)}}
function Get-FileHash {param($LiteralPath,$Algorithm);[pscustomobject]@{Hash='MODELED'}}
$originalOrigin=${function:Get-ConfigurationOrigins};$originalVpn=${function:Get-VpnInterfaceContext}
foreach($failed in @('ConfigurationOrigins','VpnInterfaceContext')){
    $script:originCalls=0;$script:vpnCalls=0
    function Get-ConfigurationOrigins {param($Checks);$script:originCalls++;if($failed -eq 'ConfigurationOrigins'){throw 'origin <fault>'};& $originalOrigin $Checks}
    function Get-VpnInterfaceContext {param($Checks);$script:vpnCalls++;if($failed -eq 'VpnInterfaceContext'){throw 'vpn <fault>'};& $originalVpn $Checks}
    $e=New-DhcpReviewFixture;$p=Write-DiagnosticReport $e $work
    $saved=$script:files[$p.JsonPath]|ConvertFrom-Json;$html=$script:files[$p.HtmlPath]
    Assert ($saved.Checks.Count -gt 0 -and $saved.Analysis.Status -eq 'Partial' -and $saved.Publication.Html -eq 'Published') 'Isolated failure must preserve raw evidence and HTML'
    Assert ($script:originCalls -eq 1 -and $script:vpnCalls -eq 1) 'Renderer recomputed analysis'
    Assert ($html.Contains($failed) -and $html.Contains('&lt;fault&gt;')) 'HTML must describe the failed section safely'
}
foreach($partial in @($false,$true)){
    $script:time=0;$script:raw=@()
    $fixture=New-DhcpReviewFixture
    $fixture.Checks[0].Data=@($fixture.Checks[0].Data[0]);$fixture.Checks[1].Data=@($fixture.Checks[1].Data[0])
    $fixture.Checks[1].Data[0].DefaultIPGateway=@();$fixture.Checks[1].Data[0].DNSServerSearchOrder=@()
    $fixture.Checks[2].Data=@()
    $execute={param($definition,$timeout,$directory)
        $script:time+=0.01
        if($partial -and $definition.Name -eq 'Routes'){$script:time=10}
        $data=@($fixture.Checks | Where-Object Name -eq $definition.Name | ForEach-Object {$_.Data})
        if($definition.Name -eq 'DNSServers'){$data=@([pscustomobject]@{InterfaceIndex=1;AddressFamily=2;ServerAddresses=@()})}
        [pscustomobject]@{Name=$definition.Name;Status='Success';Data=$data;Error=$null}
    }
    $run=Invoke-ObservationRun -RepositoryRoot $root -OutputRoot $work -DurationSeconds 10 -IntervalSeconds 5 -CheckExecutor $execute -ElapsedClock {$script:time} -WaitAction {param($seconds);$script:time+=$seconds}
    $sample=$script:files[(Join-Path $run.Directory 'sample-0000.json')]|ConvertFrom-Json
    $identity=$sample.ContextEvidence.Current.Identity
    Assert ($identity.CollectionStatus -eq $sample.CollectionStatus -and $identity.CompletedAt -eq $sample.CompletedAt) 'Embedded identity differs from sample'
    $expected=if($partial){'Incomplete'}else{'ObservedEmpty'}
    foreach($field in @('IPv4','Gateways','DnsServers')){Assert ($sample.DhcpSummary.Interfaces[0].Availability.$field -eq $expected) "Unexpected $field coverage: $expected"}
    $pending=@($script:raw | Where-Object {$_.CompletedAt -and $_.Analysis.Status -eq 'Pending'})
    Assert ($pending.Count -gt 0) 'Truthful raw collection checkpoint missing before analysis'
}
Write-Host 'PASS: isolated analysis/rendering and completed/partial serialized empty-configuration context; modeled persistence.'
