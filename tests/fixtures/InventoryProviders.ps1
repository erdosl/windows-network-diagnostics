function New-TestAdapterInventory {
    $names=@('Ethernet','Ethernet 2','Lab [1]','Lab ?','Lab * with spaces','Tunnel absent')
    $names+=@(1..8 | ForEach-Object { 'Local Area Connection* '+$_ })
    for($i=0;$i -lt $names.Count;$i++){
        [pscustomobject]@{Name=$names[$i];InterfaceIndex=($i+1);InterfaceGuid=('11111111-1111-1111-1111-{0:d12}' -f ($i+1))
            InterfaceDescription=$(if($i -lt 2){'Similar installation '+$i}elseif($i -ge 6){'Synthetic WAN miniport '+$i}else{'Synthetic device '+$i})
            Status=$(if($i -eq 5){'Not Present'}else{'Up'});HardwareInterface=($i -lt 2)}
    }
}
function Get-NetAdapter {
    [CmdletBinding()]param($Name,[switch]$IncludeHidden,$InterfaceDescription,$InterfaceIndex)
    if(-not $IncludeHidden -or $PSBoundParameters.ContainsKey('Name') -or
        $PSBoundParameters.ContainsKey('InterfaceDescription') -or $PSBoundParameters.ContainsKey('InterfaceIndex')){throw 'Inventory must be unfiltered with hidden rows included'}
    New-TestAdapterInventory
}
