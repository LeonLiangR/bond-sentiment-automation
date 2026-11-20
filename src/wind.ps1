param([Parameter(Mandatory=$true)][string]$InputFile,[Parameter(Mandatory=$true)][string]$OutputFile,[ValidateRange(1,240)][int]$TimeoutSeconds=120)
. (Join-Path $PSScriptRoot 'wps-common.ps1')
$samples=Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8|ConvertFrom-Json
if($samples.Count -eq 0){throw 'Empty Wind input'}
$app=$null;$book=$null;$owned=$false;$sheet=$null;$retryState=$null
$windClock=[Diagnostics.Stopwatch]::StartNew();$windLast=0
function Wind-Progress([string]$Phase){$now=$windClock.ElapsedMilliseconds;[IO.File]::AppendAllText((Join-Path (Split-Path -Parent $OutputFile) 'wind-timings.jsonl'),(([ordered]@{phase=$Phase;elapsedMs=($now-$script:windLast);totalMs=$now}|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));$script:windLast=$now;[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputFile) 'wind-progress.json'),([ordered]@{phase=$Phase;engine=(Get-SpreadsheetSpec).engine;time=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))}
try {
 if(Test-Path -LiteralPath $OutputFile){Remove-Item -LiteralPath $OutputFile -Force}
 Wind-Progress 'start-office'
 $app=Open-OwnedSpreadsheet (Split-Path -Parent $OutputFile);$owned=$true
 Wind-Progress 'check-addin'
 $connected=$false;foreach($addin in $app.COMAddIns){if($addin.ProgId -eq 'WDF.Addin'){if(-not $addin.Connect){try{$addin.Connect=$true}catch{}};if($addin.Connect){$connected=$true}}}
 if(-not $connected){throw ((Get-SpreadsheetSpec).name+' Wind add-in WDF.Addin is not connected; install and enable its matching Wind plugin')}
 Wind-Progress 'create-workbook'
 $book=$app.Workbooks.Add();Set-OwnedSpreadsheetBackground $app;$sheet=$book.Worksheets.Item(1)
 # Excel's Wind asynchronous dependencies do not reliably finish in manual/range-only mode.
 if((Get-SpreadsheetSpec).engine -eq 'excel'){$app.Calculation=-4105}else{try{$app.Calculation=-4135}catch{}}
 $names=New-Object 'object[,]' $samples.Count,1
 $formulas=New-Object 'object[,]' $samples.Count,12
 $functions=@('to_windcode','b_info_issuerupdated','b_agency_guarantor','b_info_windl2type','b_info_term','b_info_eobspecialinstrutions','b_info_greenbond','b_info_isscitechbond','b_info_subordinateornot','b_issue_firstissue','b_tender_paymentdate','bookrunner')
 for($i=0;$i -lt $samples.Count;$i++){
  $r=$i+2;$names[$i,0]=$samples[$i].name
  for($j=0;$j -lt 12;$j++){$inputCol=if($j -eq 0){'A'}else{'B'};$formulas[$i,$j]='='+$functions[$j]+'('+$inputCol+$r+')'}
 }
 $last=$samples.Count+1
 $sheet.Range('A2:A'+$last).Value2=$names
 Wind-Progress 'write-formulas'
 $sheet.Range('B2:M'+$last).Formula=$formulas
 Wind-Progress 'calculate'
 if((Get-SpreadsheetSpec).engine -eq 'excel'){$app.CalculateFull()}else{$sheet.Range('A2:M'+$last).Calculate()}
 Wind-Progress 'read-results'
 $keys=@('code','issuer','guarantor','windType','term','option','green','science','subordinate','issueDate','paymentDate','bookrunner')
 function Read-OriginalWindRows {
  $block=$sheet.Range('B2:M'+$last).Value2;$rows=@()
  for($i=0;$i -lt $samples.Count;$i++){
   $item=[ordered]@{sampleId=$samples[$i].sampleId;name=$samples[$i].name}
   for($j=0;$j -lt 12;$j++){$item[$keys[$j]]=$block.GetValue($i+1,$j+1)}
   $rows+=$item
  }
  $rows
 }
 $retryState=@{sheet=$null;samples=[Collections.Generic.List[object]]::new();ids=@{}}
 function Start-WindNameRetry($Rows,$Ids){
  $selected=@($Rows|Where-Object {$_.sampleId -in $Ids -and -not $retryState.ids.ContainsKey([string]$_.sampleId) -and (Get-WindRetryName $_)})
  if(-not $selected.Count){return}
  if(-not $retryState.sheet){
   [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputFile) 'wind-before-name-retry.json'),(ConvertTo-Json -InputObject @($Rows) -Depth 8),[Text.UTF8Encoding]::new($false))
   $retryState.sheet=$book.Worksheets.Add();Set-OwnedSpreadsheetBackground $app
  }
  Wind-Progress 'retry-without-final-A-B'
  $first=$retryState.samples.Count+2;$retryNames=New-Object 'object[,]' $selected.Count,1;$retryFormulas=New-Object 'object[,]' $selected.Count,12
  for($i=0;$i -lt $selected.Count;$i++){
   $sample=$selected[$i];$query=Get-WindRetryName $sample;$retryState.samples.Add([ordered]@{sampleId=$sample.sampleId;name=$sample.name;query=$query});$retryState.ids[[string]$sample.sampleId]=$true
   $r=$first+$i;$retryNames[$i,0]=$query
   for($j=0;$j -lt 12;$j++){$col=if($j -eq 0){'A'}else{'B'};$retryFormulas[$i,$j]='='+$functions[$j]+'('+$col+$r+')'}
  }
  $retryState.sheet.Range('A'+$first).Resize($selected.Count,1).Value2=$retryNames
  $retryState.sheet.Range('B'+$first).Resize($selected.Count,12).Formula=$retryFormulas
  if((Get-SpreadsheetSpec).engine -eq 'excel'){$app.CalculateFull()}else{$retryState.sheet.Range('A'+$first).Resize($selected.Count,13).Calculate()}
 }
 function Read-CombinedWindRows {
  $original=@(Read-OriginalWindRows)
  if(-not $retryState.samples.Count){$original;return}
  $block=$retryState.sheet.Range('B2').Resize($retryState.samples.Count,12).Value2;$retryRows=@()
  for($i=0;$i -lt $retryState.samples.Count;$i++){$item=[ordered]@{sampleId=$retryState.samples[$i].sampleId;name=$retryState.samples[$i].name};for($j=0;$j -lt 12;$j++){$item[$keys[$j]]=$block.GetValue($i+1,$j+1)};$retryRows+=,$item}
  Join-WindNameRetryRows $original $retryRows @($retryState.samples.ToArray())
 }
 # Only stable zero-valued A/B samples are retried early. Other asynchronous rows
 # continue to be read within the original 120-second window.
 $result=Wait-WindRows -ExpectedCount $samples.Count -TimeoutSeconds $TimeoutSeconds -AllowPartial -EarlyRetrySeconds 10 -OnEarlyRetry {param($rows,$ids) Start-WindNameRetry $rows $ids} -ReadRows {Read-CombinedWindRows}
 $late=@($result.rows|Where-Object {-not $retryState.ids.ContainsKey([string]$_.sampleId) -and (Get-WindRetryName $_)})
 if($late.Count){
  # An A/B sample can become zero only at the deadline; still try its suffix once.
  Start-WindNameRetry $late @($late|ForEach-Object sampleId)
  $elapsed=$result.elapsedSeconds;$result=Wait-WindRows -ExpectedCount $samples.Count -TimeoutSeconds $TimeoutSeconds -AllowPartial -ReadRows {Read-CombinedWindRows};$result.elapsedSeconds+=$elapsed
 }
 if($retryState.samples.Count){[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputFile) 'wind-name-retry.json'),(ConvertTo-Json -InputObject @($result.rows|Where-Object {$_.windRetry}) -Depth 8),[Text.UTF8Encoding]::new($false))}
 [IO.File]::WriteAllText($OutputFile,$result.json,[Text.UTF8Encoding]::new($false))
 Wind-Progress 'complete'
 [ordered]@{rows=$result.rows.Count;visible=$app.Visible;independent=$owned;stable=$result.stable;elapsedSeconds=$result.elapsedSeconds}|ConvertTo-Json -Compress
} catch {
 Wind-Progress 'failed';throw
} finally {
 if($retryState){Release-SpreadsheetCom $retryState.sheet};Release-SpreadsheetCom $sheet;Close-OwnedSpreadsheet $app $book
}
