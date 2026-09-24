#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\Observation.ps1')
. (Join-Path $PSScriptRoot 'fixtures\DhcpReview.ps1')
$count=0
function Assert($ok,$message){if(-not $ok){throw $message};$script:count++}
foreach($counts in @(@(0,1),@(1,0),@(0,0),@(1,1),@(2,2))){
    $a=Get-ObservationDhcpState (New-DhcpReviewFixture).Checks
    $b=Get-ObservationDhcpState (New-DhcpReviewFixture).Checks
    foreach($pair in @(@($a,$counts[0]),@($b,$counts[1]))){
        $objects=@()
        for($i=0;$i -lt $pair[1];$i++){$objects+=[pscustomobject]@{Name="Synthetic $i";Status=$null}}
        $pair[0].Records[0].AdapterContext=$objects
    }
    $result=Compare-ObservationDhcpState $a $b
    $json=ConvertTo-Json -InputObject $result -Depth 20
    $round=$json | ConvertFrom-Json
    foreach($side in @('Before','After')){
        $expected=$(if($side -eq 'Before'){$counts[0]}else{$counts[1]})
        $value=$round.Adapters[0].($side+'AdapterContext')
        Assert ($value -is [array] -and $value.Count -eq $expected) "$side serialized collection has expected array shape"
        if($expected){
            Assert ($value[0].PSObject.Properties.Name -contains 'Status' -and $null -eq $value[0].Status) 'Valid context null property retained'
        }else{Assert ($json -match ('"'+$side+'AdapterContext":\s*\[\s*\]')) 'Absent context encoded as []'}
    }
    Assert ($round.Outcome -eq 'Unchanged' -and $round.Coverage -eq 'Complete' -and $round.Adapters[0].BeforeEvidence.Count -eq 1) 'Comparison semantics and references preserved'
}
Write-Host "PASS: $count serialized observation context assertions on $($PSVersionTable.PSVersion)."
