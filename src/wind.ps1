param([Parameter(Mandatory=$true)][string]$InputFile,[Parameter(Mandatory=$true)][string]$OutputFile,[ValidateRange(1,240)][int]$TimeoutSeconds=120)
. (Join-Path $PSScriptRoot 'wps-common.ps1')
$samples=Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8|ConvertFrom-Json
if($samples.Count -eq 0){throw 'Empty Wind input'}
$app=$null;$book=$null;$owned=$false;$sheet=$null
function Wind-Progress([string]$Phase){[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $OutputFile) 'wind-progress.json'),([ordered]@{phase=$Phase;engine=(Get-SpreadsheetSpec).engine;time=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))}
try {
 if(Test-Path -LiteralPath $OutputFile){Remove-Item -LiteralPath $OutputFile -Force}
 Wind-Progress 'start-office'
 $app=Open-OwnedSpreadsheet (Split-Path -Parent $OutputFile);$owned=$true
 Wind-Progress 'check-addin'
 $connected=$false;foreach($addin in $app.COMAddIns){if($addin.ProgId -eq 'WDF.Addin'){if(-not $addin.Connect){try{$addin.Connect=$true}catch{}};if($addin.Connect){$connected=$true}}}
 if(-not $connected){throw ((Get-SpreadsheetSpec).name+' Wind add-in WDF.Addin is not connected; install and enable its matching Wind plugin')}
 Wind-Progress 'create-workbook'
 $book=$app.Workbooks.Add();$sheet=$book.Worksheets.Item(1)
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
 $result=Wait-WindRows -ExpectedCount $samples.Count -TimeoutSeconds $TimeoutSeconds -ReadRows {
  $block=$sheet.Range('B2:M'+$last).Value2;$rows=@()
  for($i=0;$i -lt $samples.Count;$i++){
   $item=[ordered]@{sampleId=$samples[$i].sampleId;name=$samples[$i].name}
   for($j=0;$j -lt 12;$j++){$item[$keys[$j]]=$block.GetValue($i+1,$j+1)}
   $rows+=$item
  }
  $rows
 }
 [IO.File]::WriteAllText($OutputFile,$result.json,[Text.UTF8Encoding]::new($false))
 Wind-Progress 'complete'
 [ordered]@{rows=$result.rows.Count;visible=$app.Visible;independent=$owned;stable=$result.stable;elapsedSeconds=$result.elapsedSeconds}|ConvertTo-Json -Compress
} catch {
 Wind-Progress 'failed';throw
} finally {
 Release-SpreadsheetCom $sheet;Close-OwnedSpreadsheet $app $book
}
