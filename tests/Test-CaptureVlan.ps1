#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Capture.ps1')
Add-Type -Path (Join-Path $root 'src\CaptureDecoder.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures\CaptureFixture.cs')
$work=Join-Path $root ('output\tests\vlan-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $work
$script:count=0
function Assert($value,$message){if(-not $value){throw $message};$script:count++}
function Decode($ta,$ca,$tb,$cb,[bool]$truncated=$false){
    $path=Join-Path $work ([guid]::NewGuid().ToString()+'.pcapng')
    [NetworkDiagnostics.Tests.CaptureFixture]::WriteVlan($path,[uint16[]]$ta,[uint16[]]$ca,[uint16[]]$tb,[uint16[]]$cb,$truncated)
    [NetworkDiagnostics.CaptureDecoder]::Decode($path,100)
}
$d=Decode @(33024) @(10) @(33024) @(20)
$o=@(Get-CaptureObservations $d.Packets)
Assert (@($o|Where-Object {$_.Kind -eq 'DhcpTransaction' -and $_.ClientIdentifier -eq '010A'}).Count -eq 2) 'DHCP VLAN separation'
Assert (@($o|Where-Object Kind -eq 'ArpClaims').Count -eq 0) 'ARP VLAN separation'
Assert ($d.Packets[0].VlanTags[0].TPID -eq 33024 -and $d.Packets[0].VlanTags[0].TCI -eq 10) 'Raw TPID and TCI'
$d=Decode @(33024) @(10) @(33024) @(45066)
$o=@(Get-CaptureObservations $d.Packets)
Assert (@($o|Where-Object {$_.Kind -eq 'DhcpTransaction' -and $_.ClientIdentifier -eq '010A'}).Count -eq 1) 'PCP DEI do not split DHCP scope'
Assert (@($o|Where-Object Kind -eq 'ArpClaims').Count -eq 1) 'Same VLAN ARP still correlates'
Assert ($d.Packets[1].VlanTags[0].PCP -eq 5 -and $d.Packets[1].VlanTags[0].DEI -eq 1 -and $d.Packets[1].VlanTags[0].VlanId -eq 10) 'Decoded PCP DEI VID'
$d=Decode @() @() @(33024) @(0)
Assert ($d.Packets[0].VlanTags.Count -eq 0 -and (Get-CaptureVlanScope $d.Packets[1]) -eq 'Tagged/8100:0') 'Untagged distinct from VLAN zero'
Assert (@(Get-CaptureObservations $d.Packets|Where-Object Kind -eq 'ArpClaims').Count -eq 0) 'Priority tag not merged with untagged'
$d=Decode @(34984,33024) @(10,20) @(34984,33024) @(20,10)
Assert (@(Get-CaptureObservations $d.Packets|Where-Object Kind -eq 'ArpClaims').Count -eq 0) 'Ordered double tag stacks separate'
Assert ((Get-CaptureVlanScope $d.Packets[0]) -eq 'Tagged/88A8:10/8100:20') 'Ordered TPID VID key'
$d=Decode @(34984,33024) @(10,20) @(33024,34984) @(10,20)
Assert (@(Get-CaptureObservations $d.Packets|Where-Object Kind -eq 'ArpClaims').Count -eq 0) 'Different ordered TPIDs separate'
$d=Decode @(34984,33024) @(10,20) @(34984,33024) @(45066,4116)
Assert (@(Get-CaptureObservations $d.Packets|Where-Object Kind -eq 'ArpClaims').Count -eq 1) 'Double-tag PCP DEI differences still correlate'
$d=Decode @(33024,33024,33024) @(1,2,3) @() @()
Assert ($d.Status -eq 'PartialOrUnsupported' -and $d.Errors[0].Message -match 'VLAN') 'Unsupported third tag explicit'
$d=Decode @() @() @() @() $true
Assert ($d.Status -eq 'PartialOrUnsupported' -and $d.Errors[0].BlockOffset -gt 0) 'Truncated tag has raw reference'
$old=[pscustomobject]@{Kind='ARP';SectionId=0;InterfaceId=0;BlockOffset=100;Operation=2;SenderProtocolAddress='192.0.2.1';SenderHardwareAddress='020000000001'}
$o=@(Get-CaptureObservations @($old))
Assert ($o[0].Outcome -eq 'Not assessed' -and $o[0].Reason -match 'absent') 'Old metadata not assumed untagged'
$old|Add-Member NoteProperty VlanTags @([pscustomobject]@{TPID=33024;TCI=10;VlanId=20})
Assert (@(Get-CaptureObservations @($old))[0].Outcome -eq 'Not assessed') 'Conflicting tag metadata unassessed'
Write-Host "PASS: $script:count VLAN assertions on $($PSVersionTable.PSVersion)."
