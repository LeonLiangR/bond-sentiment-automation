param([Parameter(Mandatory=$true)][string]$FixtureDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$FixtureDirectory=[IO.Path]::GetFullPath($FixtureDirectory);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$app=$null;$book=$null;$legacy=$null
try{
 $app=Open-OwnedSpreadsheet $OutputDirectory
 $book=$app.Workbooks.Open((Join-Path $OutputDirectory 'dq-upload-native.xlsx'),0,$true);Set-OwnedSpreadsheetBackground $app
 $rows=Get-Content -LiteralPath (Join-Path $OutputDirectory 'upload-rows.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $sheet=$book.Worksheets.Item(2);$block=$sheet.Range('A2:J101').Value2
 for($i=0;$i -lt 100;$i++){for($j=0;$j -lt 10;$j++){
  $expected=if($i -lt $rows.Count){$rows[$i][$j]}else{$null};$actual=$block.GetValue($i+1,$j+1)
  if($null -eq $expected -or $expected -eq ''){Assert ($null -eq $actual -or $actual -eq '') 'Uncleared DQ template value'}
  elseif($expected -is [string]){Assert ($actual -is [string] -and $actual -ceq $expected) ('DQ text mismatch '+$i+','+$j)}
  else{Assert ($actual -is [double] -and [math]::Abs($actual-$expected)-lt 1e-10) ('DQ number mismatch '+$i+','+$j)}
 }}
 Assert ($book.Worksheets.Count -eq 5) 'DQ worksheet count changed'
 for($k=3;$k -le 5;$k++){$b=$book.Worksheets.Item($k).Range('A2:J101').Value2;foreach($v in $b){Assert ($null -eq $v -or $v -eq '') 'Other DQ template tabs not cleared'}}
 $book.Close($false);Release-SpreadsheetCom $book;$book=$null
 $book=$app.Workbooks.Open((Join-Path $OutputDirectory 'report-optimized.xlsx'),0,$true)
 $legacy=$app.Workbooks.Open((Get-ChildItem -LiteralPath (Split-Path -Parent $FixtureDirectory) -Filter '*.xlsx'|Select-Object -First 1 -ExpandProperty FullName),0,$true)
 # Compare fonts and all historical row heights after Office has saved and reopened.
 $count=(Get-Content -LiteralPath (Join-Path $FixtureDirectory 'report-plan.json') -Raw -Encoding UTF8|ConvertFrom-Json).history.Count
 for($r=2;$r -le $count+1;$r++){
  Assert ([math]::Abs($book.Worksheets.Item(5).Rows.Item($r).RowHeight-$legacy.Worksheets.Item(5).Rows.Item($r).RowHeight)-lt 0.1) ('History row height differs: '+$r)
 }
 foreach($b in @($book,$legacy)){
  Assert ($b.Worksheets.Item(1).Range('A1').Characters(1,1).Font.Name -eq ([string][char]0x6977+[char]0x4f53)) 'Chinese font changed'
  Assert ($b.Worksheets.Item(2).Range('C1').Characters(1,2).Font.Name -eq 'Times New Roman') 'Mixed Latin font changed'
  Assert ($b.Worksheets.Item(2).Range('C1').Characters(3,1).Font.Name -eq ([string][char]0x6977+[char]0x4f53)) 'Mixed Chinese font changed'
 }
 Assert ([math]::Abs($book.Worksheets.Item(1).Range('E15').Value2-45.40816326530612)-lt 1e-8) 'Reopened report index differs'
 Assert ($book.Worksheets.Item(2).Range('M2').HasFormula) 'Scores must remain editable formulas'
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'xlsx-native-verification.json'),'{"passed":true,"dqTypedCells":1000,"historicalRowHeights":507,"reopenedFormulaAndFonts":true}',[Text.UTF8Encoding]::new($false))
 'Native DQ typed cells, cleared template tabs, saved/reopened report formulas, fonts and historical row heights passed'
}finally{if($legacy){$legacy.Close($false);Release-SpreadsheetCom $legacy};Close-OwnedSpreadsheet $app $book}
