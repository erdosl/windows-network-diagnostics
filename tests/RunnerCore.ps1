function Test-SuiteCatalog {
    param([string]$Directory,[hashtable]$Catalog,[hashtable]$Excluded=@{})
    foreach($file in Get-ChildItem -LiteralPath $Directory -Filter 'Test-*.ps1'){
        if(-not $Catalog.ContainsKey($file.BaseName) -and -not $Excluded.ContainsKey($file.BaseName)){throw "Uncategorized test suite: $($file.Name)"}
    }
    foreach($name in $Catalog.Keys){if(-not [IO.File]::Exists((Join-Path $Directory ($name+'.ps1')))){throw "Catalog suite missing: $name"}}
}

function Invoke-ValidationCatalog {
    param([string]$Root,[string]$SuiteDirectory,[string[]]$Suite,[hashtable]$Catalog,[string]$Directory,[int]$TimeoutSeconds,$Report,[scriptblock]$AfterSuite)
    $Report | Add-Member NoteProperty ValidationContractVersion 1 -Force
    $Report | Add-Member NoteProperty Status 'Incomplete' -Force
    $Report | Add-Member NoteProperty StartedAt ([DateTimeOffset]::Now.ToString('o')) -Force
    $Report | Add-Member NoteProperty CompletedAt $null -Force
    $Report | Add-Member NoteProperty PendingSuite $null -Force
    $Report | Add-Member NoteProperty Error $null -Force
    $state=@{Checkpoint=0}
    $save={
        # Immutable atomic checkpoints avoid overwriting earlier suite results.
        # A forcibly interrupted run has no final results.json; use the last
        # numbered checkpoint, which explicitly remains Incomplete.
        Set-AtomicText (Join-Path $Directory ('checkpoint-{0:D4}.json' -f $state.Checkpoint)) (ConvertTo-Json $Report -Depth 16)
        $state.Checkpoint++
    }
    & $save
    try{
        foreach($name in $Suite){
            $Report.PendingSuite=$name;& $save
            Write-Host "Running $name ($($Catalog[$name]))"
            $path=Join-Path $SuiteDirectory ($name+'.ps1')
            $result=Invoke-BoundedCheck ([pscustomobject]@{Name=$name;FunctionName='Invoke-TestSuiteFile';Arguments=@{Path=$path}}) (Join-Path $Root 'src') $Directory $TimeoutSeconds -AdditionalSources @((Join-Path $Root 'tests\fixtures\SuiteWorker.ps1')) -CapturePartialOutput
            $data=@($result.Data)|Select-Object -First 1
            $exitCode=$null;if($result.Status -eq 'Success'){$exitCode=$data.ExitCode}
            $Report.Suites+=[pscustomobject]@{Suite=$name;Command=('powershell.exe -NoProfile -NonInteractive -File "'+$path+'"');Category=$Catalog[$name];ExitCode=$exitCode;WorkerStatus=$result.Status;WorkerProcessId=$result.WorkerProcessId;DurationSeconds=$result.DurationMs/1000.0;Error=$result.Error;ProviderCoverage=$(if($Catalog[$name] -eq 'LiveProvider'){'Native'}else{'Synthetic/mocked; no native provider validation'});Collectors=$(if($Catalog[$name] -eq 'LiveProvider'){'Native inspector queries'}else{'Synthetic fixtures or mocked collectors; see suite source'});Persistence=$(if($Catalog[$name] -eq 'Model'){'Modeled'}elseif($Catalog[$name] -eq 'Persistence'){'Real atomic I/O'}else{'See suite source'});OutputLimitCharacters=65536}
            $output=$data.Output;if($null -eq $output){$output=$result.PartialOutput}
            Set-AtomicText (Join-Path $Directory ($name+'.log')) ([string]$output)
            $Report.PendingSuite=$null;& $save
            Write-Host "$name : worker=$($result.Status), exit=$exitCode"
            if($AfterSuite){& $AfterSuite $Report}
        }
        $Report.Status='Complete';$Report.CompletedAt=[DateTimeOffset]::Now.ToString('o')
    }catch{$Report.Error=$_.Exception.Message;throw}
    finally{
        & $save
        Set-AtomicText (Join-Path $Directory 'results.json') (ConvertTo-Json $Report -Depth 16)
        $passed=@($Report.Suites | Where-Object {$_.WorkerStatus -eq 'Success' -and $null -ne $_.ExitCode -and $_.ExitCode -eq 0}).Count
        Write-Host "$($Report.Status): $passed passed; $($Report.Suites.Count-$passed) failed/unavailable; $($Report.Suites.Count) recorded."
        Write-Host ('Validation record: '+(Join-Path $Directory 'results.json'))
    }
    $Report
}
