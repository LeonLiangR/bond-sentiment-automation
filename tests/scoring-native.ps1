param([Parameter(Mandatory=$true)][string]$InputFile,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$data=Get-Content -LiteralPath $InputFile -Raw|ConvertFrom-Json
$app=$null;$book=$null;$sheet=$null
try{
 $app=Open-OwnedSpreadsheet $OutputDirectory;$book=$app.Workbooks.Add();$sheet=$book.Worksheets.Item(1)
 for($i=0;$i -lt $data.cases.Count;$i++){$row=$i+2;$sheet.Range('K'+$row).Value2=[double]$data.cases[$i].spread;$sheet.Range('L'+$row).Value2=1;$sheet.Range('M'+$row).Formula=$data.formula.Replace('K2',('K'+$row)).Replace('L2',('L'+$row))}
 $app.Calculate()
 for($i=0;$i -lt $data.cases.Count;$i++){if([math]::Abs([double]$sheet.Range('M'+($i+2)).Value2-[double]$data.cases[$i].expected)-gt 1e-12){throw ('Native score differs at '+$data.cases[$i].spread)}}
 Write-Output ('Native formula boundary cases passed: '+$data.cases.Count)
}finally{Release-SpreadsheetCom $sheet;Close-OwnedSpreadsheet $app $book}
