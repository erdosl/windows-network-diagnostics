# Parent-only persistence. A publication status inside a file describes that
# publication attempt; only a successful return confirms the write completed.
function Get-ArtifactError {
    param($Record,[string]$Stage,[string]$Path)
    [pscustomobject]@{Stage=$Stage;Path=$Path;Message=$Record.Exception.Message;Id=$Record.FullyQualifiedErrorId;ExceptionType=$Record.Exception.GetType().FullName;HResult=$Record.Exception.HResult}
}

function Write-CanonicalEvidence {
    param($Evidence,[string]$Path)
    try { $json=ConvertTo-Json -InputObject $Evidence -Depth 32 -ErrorAction Stop }
    catch { $_.Exception.Data['ArtifactStage']='JsonSerialization';$_.Exception.Data['ArtifactPath']=$Path;throw }
    try { Set-AtomicText -Path $Path -Text $json }
    catch { $_.Exception.Data['ArtifactStage']='CanonicalPublication';$_.Exception.Data['ArtifactPath']=$Path;throw }
}

function Invoke-ReportAnalysis {
    param($Evidence)
    $sections=@(
        @{Name='Findings';Fields=@('Findings');Action={Get-DiagnosticFindings $Evidence.Checks}},
        @{Name='LogicalNetwork';Fields=@('LogicalNetwork');Action={Get-LogicalNetworkModel $Evidence}},
        @{Name='DhcpContext';Fields=@('DhcpSummary','SnapshotComparison','ExpectationAssessment','HistoricalEventContext');Action={Update-DhcpContext $Evidence}},
        @{Name='ConfigurationOrigins';Fields=@('ConfigurationOrigins');Action={@(Get-ConfigurationOrigins $Evidence.Checks)}},
        @{Name='VpnInterfaceContext';Fields=@('VpnInterfaceContext');Action={@(Get-VpnInterfaceContext $Evidence.Checks)}}
    )
    foreach($section in $sections){
        foreach($field in $section.Fields){$Evidence | Add-Member NoteProperty $field $null -Force}
        $entry=[pscustomobject]@{Section=$section.Name;Status='Complete';EvidenceRevision=$Evidence.Revision;Error=$null}
        try {
            $value=& $section.Action
            if($section.Name -ne 'DhcpContext'){$Evidence | Add-Member NoteProperty $section.Name $value -Force}
        } catch {
            foreach($field in $section.Fields){$Evidence | Add-Member NoteProperty $field $null -Force}
            $entry.Status='Failed';$entry.Error=Get-ArtifactError $_ 'Analysis' $section.Name
        }
        $Evidence.Analysis.Sections+= $entry
    }
    $Evidence.Analysis.Status=$(if(@($Evidence.Analysis.Sections | Where-Object Status -eq 'Failed').Count){'Partial'}else{'Complete'})
}

function Write-DiagnosticReport {
    param([Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)][string]$OutputDirectory,[switch]$RawOnly)
    $null=[IO.Directory]::CreateDirectory($OutputDirectory)
    $jsonPath=Join-Path $OutputDirectory 'evidence.json';$htmlPath=Join-Path $OutputDirectory 'summary.html'
    if(-not $Evidence.PSObject.Properties['Revision']){$Evidence | Add-Member NoteProperty Revision 0}
    # Normalize the already-bounded baseline input into its canonical source
    # store before the raw checkpoint, so its scoped references resolve even
    # while current-snapshot analysis is still pending. No analysis runs here.
    $baseline=$Evidence.ContextEvidence.Baseline
    foreach($inputCheck in @($Evidence.ContextInputs | Where-Object { $_.Name -eq 'Baseline' -and $_.Status -eq 'Success' })){
        $candidate=@($inputCheck.Data) | Select-Object -First 1
        if($candidate.Identity -and $candidate.PSObject.Properties['Checks']){$baseline=$candidate}
        if($baseline){$inputCheck.Data=@([pscustomobject]@{Scope='Baseline';RunId=$baseline.Identity.RunId;Path='/ContextEvidence/Baseline'})}
    }
    $Evidence | Add-Member NoteProperty ContextEvidence ([pscustomobject]@{ContractVersion=4;Current=[pscustomobject]@{Identity=($Evidence | Select-Object ComputerName,RunId,StartedAt,CompletedAt,CollectionStatus);ChecksPath='/Checks'};Baseline=$baseline}) -Force
    $Evidence | Add-Member NoteProperty Analysis ([pscustomobject]@{ContractVersion=1;Status='Pending';EvidenceRevision=$Evidence.Revision;Sections=@()}) -Force
    $Evidence | Add-Member NoteProperty Publication ([pscustomobject]@{ContractVersion=1;Canonical='Published';EvidenceRevision=$Evidence.Revision;Html='Pending';HtmlEvidenceRevision=$null;Error=$null}) -Force
    if($Evidence.Metadata){
        $os=@($Evidence.Checks | Where-Object Name -eq 'Windows' | Select-Object -Last 1)
        if($os.Count){
            $Evidence.Metadata.OS.WindowsCheckPath='/Checks/'+[array]::IndexOf(@($Evidence.Checks),$os[0])
            $Evidence.Metadata.OS.Status=$os[0].Status
            $Evidence.Metadata.OS.Reason=$(if($os[0].Status -eq 'Success'){'See raw Windows check; runtime version is separately attributed.'}else{$os[0].Error.Message})
        }
    }
    foreach($name in @('Findings','LogicalNetwork','DhcpSummary','SnapshotComparison','ExpectationAssessment','HistoricalEventContext','ConfigurationOrigins','VpnInterfaceContext')){$Evidence | Add-Member NoteProperty $name $null -Force}
    # Persist the newest raw checks before any analysis or rendering can fail.
    Write-CanonicalEvidence $Evidence $jsonPath
    if($RawOnly){return [pscustomobject]@{JsonPath=$jsonPath;HtmlPath=$htmlPath}}
    Invoke-ReportAnalysis $Evidence
    Write-CanonicalEvidence $Evidence $jsonPath
    try {
        $Evidence.Publication.Html='Published';$Evidence.Publication.HtmlEvidenceRevision=$Evidence.Revision
        $html=ConvertTo-DiagnosticHtml $Evidence $OutputDirectory
        Set-AtomicText $htmlPath $html
    } catch {
        $failure=$_;$Evidence.Publication.Html='Failed';$Evidence.Publication.Error=Get-ArtifactError $_ 'Html' $htmlPath
        try { Write-CanonicalEvidence $Evidence $jsonPath }
        catch { $_.Exception.Data['HtmlError']=$failure;throw }
        $failure.Exception.Data['ArtifactStage']='Html';$failure.Exception.Data['ArtifactPath']=$htmlPath
        throw $failure
    }
    Write-CanonicalEvidence $Evidence $jsonPath
    [pscustomobject]@{JsonPath=$jsonPath;HtmlPath=$htmlPath}
}

function ConvertTo-RunOverviewHtml {
    param($Evidence)
    $encode={param($v)[Net.WebUtility]::HtmlEncode([string]$v)}
    $html='<section><h2>Run outcome</h2><p>Collection: '+(& $encode $Evidence.CollectionStatus)+'; analysis: '+(& $encode $Evidence.Analysis.Status)+'; canonical publication: '+(& $encode $Evidence.Publication.Canonical)+'; HTML: '+(& $encode $Evidence.Publication.Html)+'. Evidence revision '+(& $encode $Evidence.Revision)+'.</p><p>Competing DHCP servers: not assessed.</p>'
    $html+='<p>Publication labels describe this artifact generation. The command result confirms completion; consult canonical JSON if this HTML is older.</p>'
    $html+='<h3>Assessed changes</h3>'+(ConvertTo-ComparisonRowsHtml @($Evidence.SnapshotComparison.Changes | Where-Object {$null -ne $_ -and $_.Outcome -notin @('Unchanged','Not assessed')}))
    $html+='<h3>Coverage gaps by reason</h3><ul>'
    foreach($group in @($Evidence.Checks | Where-Object Status -ne 'Success' | Group-Object { $_.Status+' / '+$(if($_.Error.Id){$_.Error.Id}elseif($_.Error.Explanation){$_.Error.Explanation}else{'See raw source reason'}) })){$html+='<li>'+(& $encode $group.Name)+': '+$group.Count+' ('+(& $encode ($group.Group.Name -join ', '))+')</li>'}
    foreach($section in @($Evidence.Analysis.Sections | Where-Object Status -eq 'Failed')){$html+='<li>Analysis unavailable: '+(& $encode $section.Section)+'; '+(& $encode $section.Error.Message)+'</li>'}
    $html+='</ul><h3>Expectations mismatches (supplied policy)</h3><pre>'+(& $encode (ConvertTo-Json -InputObject @($Evidence.ExpectationAssessment.Results | Where-Object Outcome -eq 'Mismatch') -Depth 10))+'</pre>'
    $html+='<h3>Event query coverage</h3><pre>'+(& $encode (ConvertTo-Json -InputObject @(Get-EventCoverageSummary $Evidence.Checks) -Depth 8))+'</pre>'
    $html+=ConvertTo-DnsPolicyHtml $Evidence
    $html+='<h3>Interface and route context</h3><p>Default routes are predictions, not observed socket endpoints. Disconnected interfaces remain visible.</p>'
    foreach($i in @($Evidence.DhcpSummary.Interfaces | Where-Object {$null -ne $_})){
        $reference=[pscustomobject]@{Path=('/DhcpSummary/Interfaces/'+[array]::IndexOf(@($Evidence.DhcpSummary.Interfaces),$i))}
        $html+='<details><summary>'+(& $encode ($i.Alias+'; interface '+$i.InterfaceIndex+'; '+$i.Values.LinkState))+'</summary><pre>'+(& $encode (ConvertTo-Json $i.Values -Depth 8))+'</pre>'+(ConvertTo-ContextLink $reference 'Interface source coverage and evidence')+'</details>'
    }
    $html+='<h3>Requested probe outcomes and stages</h3>'
    foreach($check in @($Evidence.Checks | Where-Object Name -like 'Connectivity:*')){
        $reference=[pscustomobject]@{Path=('/Checks/'+[array]::IndexOf(@($Evidence.Checks),$check))}
        $html+='<details open><summary>'+(& $encode ($check.Name+'; collection '+$check.Status))+'</summary>'
        foreach($probe in $check.Data){$html+='<p>Outcome: '+(& $encode $probe.Outcome)+'; completed stages: '+(& $encode ($probe.CompletedStages -join ', '))+'; timeout scope: '+(& $encode $probe.TimeoutScope)+'</p>'}
        $html+=(ConvertTo-ContextLink $reference 'Raw probe evidence, route prediction and observed socket endpoints')+'</details>'
    }
    $html+'</section>'
}

function Invoke-ObservationAnalysis {
    param($Sample,$Previous,[string]$BeforeArtifact,[string]$AfterArtifact)
    $Sample | Add-Member NoteProperty Revision $Sample.Checks.Count -Force
    $Sample | Add-Member NoteProperty Analysis ([pscustomobject]@{ContractVersion=1;Status='Complete';EvidenceRevision=$Sample.Revision;Sections=@();Errors=@()}) -Force
    foreach($section in @('DhcpContext','Changes','CounterDeltas')){
        $entry=[pscustomobject]@{Section=$section;Status='Complete';EvidenceRevision=$Sample.Revision;Error=$null}
        try {
            switch($section){
                DhcpContext {Update-DhcpContext $Sample}
                Changes {
                    $Sample.Changes=@()
                    if($Previous){$Sample.Changes=@(Compare-ObservationState (Get-ObservationState $Previous.Checks $Previous.CollectionStatus) (Get-ObservationState $Sample.Checks $Sample.CollectionStatus) $BeforeArtifact $AfterArtifact)}
                    foreach($change in $Sample.Changes){
                        $change | Add-Member NoteProperty Interval ([pscustomobject]@{BeforeStartedAt=$Previous.StartedAt;AfterStartedAt=$Sample.StartedAt;ElapsedSeconds=$Sample.ActualIntervalSeconds;Limitation='Changes occurred somewhere between samples; nearby events are temporal context, not cause.'}) -Force
                        $change | Add-Member NoteProperty BeforeEvidence ([pscustomobject]@{Scope='Observation';RunId=$Sample.RunId;Artifact=$BeforeArtifact;SourceCheck=$(if(@($Previous.Checks | Where-Object Name -eq $change.Source).Count){$change.Source}else{$null});SourceAvailability=$(if(@($Previous.Checks | Where-Object Name -eq $change.Source).Count){'Present'}else{'Missing'})}) -Force
                        $change | Add-Member NoteProperty AfterEvidence ([pscustomobject]@{Scope='Observation';RunId=$Sample.RunId;Artifact=$AfterArtifact;SourceCheck=$(if(@($Sample.Checks | Where-Object Name -eq $change.Source).Count){$change.Source}else{$null});SourceAvailability=$(if(@($Sample.Checks | Where-Object Name -eq $change.Source).Count){'Present'}else{'Missing'})}) -Force
                    }
                }
                CounterDeltas {$Sample.CounterDeltas=@();if($Previous){$Sample.CounterDeltas=@(Get-CounterDeltas $Previous $Sample $Sample.ActualIntervalSeconds)}}
            }
        } catch {
            if($section -eq 'DhcpContext'){foreach($field in @('DhcpSummary','SnapshotComparison','ExpectationAssessment','HistoricalEventContext')){$Sample | Add-Member NoteProperty $field $null -Force}}
            else{$Sample.$section=@()}
            $entry.Status='Failed';$entry.Error=Get-ArtifactError $_ 'ObservationAnalysis' $AfterArtifact
            $Sample.Analysis.Errors+=$entry.Error;$Sample.Analysis.Status='Partial'
        }
        $Sample.Analysis.Sections+=$entry
    }
}
