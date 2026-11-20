param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$app=$null;$book=$null;$sheet=$null
try{
 $app=Open-OwnedSpreadsheet $OutputDirectory;$book=$app.Workbooks.Add();$sheet=$book.Worksheets.Item(1)
 $sheet.Range('A1:D1').NumberFormat='@'
 $rows=@(,@('3.13',[double]3.13,'0012','=1+1'))
 Write-Block $sheet 'A1' $rows
 $actual=$sheet.Range('A1:D1').Value2
 if($actual[1,1] -isnot [string] -or $actual[1,1] -ne '3.13' -or $actual[1,2] -is [string] -or $actual[1,2] -ne 3.13 -or $actual[1,3] -ne '0012' -or $actual[1,4] -ne '=1+1'){throw 'Typed bulk write did not preserve original values'}
 Write-Output 'Native typed write passed: numeric text, number, leading zeros and formula-like text'
}finally{Release-SpreadsheetCom $sheet;Close-OwnedSpreadsheet $app $book}
