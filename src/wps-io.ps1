param([ValidateSet('extract','upload')][string]$Mode,[string]$File,[string]$InputFile,[string]$OutputFile,[string]$RunDirectory)
. (Join-Path $PSScriptRoot 'wps-common.ps1')
$app=$null;$book=$null
try{
 $app=Open-OwnedWps $RunDirectory;$book=$app.Workbooks.Open($File,0,$Mode -eq 'extract')
 if($Mode -eq 'extract'){
  $sheet=$book.Worksheets.Item(1);$block=$sheet.UsedRange.Value2;$rowCount=$block.GetLength(0);$colCount=$block.GetLength(1);$header=0
  for($i=1;$i -le $rowCount;$i++){if([string]$block.GetValue($i,1) -eq ([string][char]0x503a+[char]0x5238+[char]0x7b80+[char]0x79f0)){$header=$i;break}}
  if(-not $header){throw 'DM data header not found'};$cols=$colCount;while($cols -gt 7 -and $null -eq $block.GetValue($header,$cols)){$cols--}
  $headers=@();for($j=1;$j -le $cols;$j++){$headers+=$block.GetValue($header,$j)};$rows=@()
  for($i=$header+1;$i -le $rowCount;$i++){if($null -eq $block.GetValue($i,1) -or $null -eq $block.GetValue($i,2)){continue};$values=@();for($j=1;$j -le $cols;$j++){$values+=$block.GetValue($i,$j)};$rows+=[ordered]@{row=$i;name=$values[0];type=$values[1];coupon=$values[6];values=$values}}
  $result=[ordered]@{title=[string]$sheet.Range('A2').Value2;headerRow=$header;headers=$headers;rows=$rows};$json=ConvertTo-Json -InputObject $result -Depth 8
  [IO.File]::WriteAllText($OutputFile,$json,[Text.UTF8Encoding]::new($false));[ordered]@{rows=$rows.Count;columns=$cols}|ConvertTo-Json -Compress
 }else{
  $rows=Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8|ConvertFrom-Json;if($book.Worksheets.Count -ne 5){throw 'Unexpected DQ official template layout'};for($i=2;$i -le 5;$i++){$book.Worksheets.Item($i).Range('A2:J101').ClearContents()|Out-Null};Write-Block $book.Worksheets.Item(2) 'A2' $rows;$book.SaveAs($OutputFile,51);[ordered]@{rows=$rows.Count;bytes=(Get-Item -LiteralPath $OutputFile).Length}|ConvertTo-Json -Compress
 }
}finally{Close-OwnedWps $app $book}
