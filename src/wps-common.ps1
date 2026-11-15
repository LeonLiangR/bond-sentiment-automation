$ErrorActionPreference='Stop'
if(-not ('SentimentOfficeWindow' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class SentimentOfficeWindow{[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);}' }
$script:OwnedOffice=@{}
function Get-SpreadsheetSpec {
 $engine=if($env:SENTIMENT_OFFICE_ENGINE){$env:SENTIMENT_OFFICE_ENGINE}else{'wps'}
 switch($engine){
  'wps' {return [pscustomobject]@{engine='wps';name='WPS';progId='ket.Application';processName='et';exe=if($env:SENTIMENT_OFFICE_PATH){$env:SENTIMENT_OFFICE_PATH}else{$env:SENTIMENT_WPS_PATH}}}
  'excel' {return [pscustomobject]@{engine='excel';name='Excel';progId='Excel.Application';processName='EXCEL';exe=$env:SENTIMENT_OFFICE_PATH}}
  default {throw 'Unsupported spreadsheet engine; choose WPS or Excel'}
 }
}
# Small native seams allow contract tests to supply fake applications without installing Office.
function New-SpreadsheetCom([string]$ProgId){return New-Object -ComObject $ProgId}
function Get-SpreadsheetProcesses {return @(Get-Process -Name et,EXCEL -ErrorAction SilentlyContinue)}
function Get-SpreadsheetProcess($Application){[uint32]$instanceId=0;[void][SentimentOfficeWindow]::GetWindowThreadProcessId([IntPtr]([long]$Application.Hwnd),[ref]$instanceId);if(-not $instanceId){throw 'Spreadsheet instance has no process identity'};return Get-Process -Id $instanceId}
function Release-SpreadsheetCom($Object){if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object)}}
function Office-Key($Application){return [string][Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Application)}
function Open-OwnedSpreadsheet([string]$TrackerDirectory){
 $spec=Get-SpreadsheetSpec;$before=@(Get-SpreadsheetProcesses|ForEach-Object Id);$application=$null;$owned=$false
 try{
  try{$application=New-SpreadsheetCom $spec.progId}catch{throw ($spec.name+' automation is unavailable. Check installation and COM registration. '+$_.Exception.Message)}
  $process=Get-SpreadsheetProcess $application
  if($process.Id -in $before){throw 'Automation returned a pre-existing spreadsheet instance; it will not be modified or closed'}
  if($process.ProcessName -notin @('et','EXCEL')){throw 'Unexpected spreadsheet process; it will not be modified or closed'}
  $key=Office-Key $application;$script:OwnedOffice[$key]=$true;$owned=$true
  $info=[ordered]@{engine=$spec.engine;processName=$process.ProcessName;processId=$process.Id;startTime=$process.StartTime.ToUniversalTime().ToString('o');path=$process.Path}
  if($TrackerDirectory){[IO.File]::AppendAllText((Join-Path $TrackerDirectory 'office-instances.jsonl'),(($info|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))}
  if($process.ProcessName -ine $spec.processName){throw ('Requested '+$spec.name+' but COM returned '+$process.ProcessName+'; no fallback is allowed')}
  if($spec.exe -and -not [string]::Equals($process.Path,$spec.exe,[StringComparison]::OrdinalIgnoreCase)){throw ($spec.name+' COM registration points to a different executable; check software paths')}
  $application.Visible=$false;$application.DisplayAlerts=$false;return $application
 }catch{
  if($owned){try{$application.Quit()}catch{};$script:OwnedOffice.Remove((Office-Key $application))}
  Release-SpreadsheetCom $application;throw
 }
}
function Open-OwnedWps([string]$TrackerDirectory){return Open-OwnedSpreadsheet $TrackerDirectory}
function Get-WindPendingFields($Rows){
 foreach($row in $Rows){
  foreach($key in @('code','issuer','guarantor','windType','term','option','green','science','subordinate','issueDate','paymentDate','bookrunner')){
   $value=$row.$key;$text=([string]$value).Trim()
   # Excel Value2 exposes VT_ERROR cells as signed HRESULT numbers, not just # text.
   $excelError=$value -is [System.Runtime.InteropServices.ErrorWrapper] -or ($value -is [ValueType] -and $value -isnot [bool] -and [double]$value -ge -2146826288 -and [double]$value -le -2146826245)
   if($excelError -or $text -match '^(?i:Fetching|Loading|Pending|#)' -or ($key -eq 'code' -and $text -notmatch '^\d{6,9}\.(IB|SH|SZ)$') -or ($key -in @('issuer','windType') -and ($value -isnot [string] -or $text -eq '0')) -or ($key -in @('issuer','windType','term','option','green','science','subordinate') -and ($null -eq $value -or $text -eq ''))){
    '{0}/{1}: {2}' -f $row.sampleId,$key,$text
   }
  }
 }
}
function Wait-WindRows([scriptblock]$ReadRows,[int]$ExpectedCount,[ValidateRange(1,240)][int]$TimeoutSeconds=120,[ValidateRange(50,5000)][int]$PollMilliseconds=1000){
 $clock=[Diagnostics.Stopwatch]::StartNew();$previous='';$readyBefore=$false;$problems=@()
 while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
  $rows=@(& $ReadRows);$problems=@(Get-WindPendingFields $rows)
  if($rows.Count -ne $ExpectedCount){$problems+='Unexpected row count'}
  $json=ConvertTo-Json -InputObject @($rows) -Depth 5
  $ready=$rows.Count -gt 0 -and $problems.Count -eq 0
  if($ready -and $readyBefore -and $json -eq $previous){return [pscustomobject]@{rows=$rows;json=$json;stable=$true;elapsedSeconds=$clock.Elapsed.TotalSeconds}}
  $readyBefore=$ready;$previous=$json
  Start-Sleep -Milliseconds $PollMilliseconds
 }
 if(-not $problems.Count){$problems=@('Results did not stabilize')}
 throw ('Wind data timeout after '+$TimeoutSeconds+'s; pending or invalid fields: '+(($problems|Select-Object -First 8) -join '; '))
}
function Matrix($Rows){$count=$Rows.Count;$cols=$Rows[0].Count;$matrix=New-Object 'object[,]' $count,$cols;for($i=0;$i -lt $count;$i++){for($j=0;$j -lt $cols;$j++){$matrix[$i,$j]=$Rows[$i][$j]}};return ,$matrix}
function Write-Block($Sheet,[string]$Cell,$Rows,[bool]$Formula=$false){if(-not $Rows -or -not $Rows.Count){return};$range=$Sheet.Range($Cell).Resize($Rows.Count,$Rows[0].Count);$matrix=Matrix $Rows;if($Formula){$range.Formula=$matrix}else{$range.Value2=$matrix}}
function Close-OwnedSpreadsheet($Application,$Book){
 $owned=$null -ne $Application -and $script:OwnedOffice.ContainsKey((Office-Key $Application))
 if($owned){if($null -ne $Book){try{$Book.Close($false)}catch{}};try{$Application.Quit()}catch{};$script:OwnedOffice.Remove((Office-Key $Application))}
 Release-SpreadsheetCom $Book;Release-SpreadsheetCom $Application;[GC]::Collect();[GC]::WaitForPendingFinalizers()
}
function Close-OwnedWps($Application,$Book){Close-OwnedSpreadsheet $Application $Book}
function Apply-ReportFonts($Book){
 $cjk=[string][char]0x6977+[char]0x4f53;$latin='Times New Roman';$nonAscii=[regex]'[^\x00-\x7f]';$ascii=[regex]'[\x00-\x7f]+'
 for($index=1;$index -le $Book.Worksheets.Count;$index++){
  $sheet=$Book.Worksheets.Item($index);$used=$sheet.UsedRange;$used.Font.Name=$latin;$values=$used.Value2;$rowBase=$used.Row;$columnBase=$used.Column
  for($i=1;$i -le $values.GetLength(0);$i++){for($j=1;$j -le $values.GetLength(1);$j++){
   $value=$values.GetValue($i,$j);if($value -isnot [string] -or -not $nonAscii.IsMatch($value)){continue};$cell=$sheet.Cells.Item($rowBase+$i-1,$columnBase+$j-1);$cell.Font.Name=$cjk
   foreach($part in $ascii.Matches($value)){$cell.Characters($part.Index+1,$part.Length).Font.Name=$latin}
  }}
 }
}
