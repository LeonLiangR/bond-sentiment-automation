param([string]$File,[string]$Snapshot,[string]$Baseline,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$expected=Get-Content -LiteralPath $Snapshot -Raw -Encoding UTF8|ConvertFrom-Json
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Same($a,$b){if(($null -eq $a -or $a -eq '') -and ($null -eq $b -or $b -eq '')){return $true};if($a -is [ValueType] -and $b -is [ValueType]){return [math]::Abs([double]$a-[double]$b)-lt 1e-10};return $a -ceq $b}
$z=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($File));try{
 $reader=[IO.StreamReader]::new($z.GetEntry('xl/worksheets/sheet1.xml').Open());try{[xml]$xml=$reader.ReadToEnd()}finally{$reader.Dispose()}
 foreach($name in @('B15','C15','D15','E15','G15','H15','I15')){$c=$xml.SelectSingleNode('//*[local-name()="c" and @r="'+$name+'"]');$formula=$c.SelectSingleNode('*[local-name()="f"]');$value=$c.SelectSingleNode('*[local-name()="v"]');Assert ($formula -and $value -and (Same ([double]$value.InnerText) $expected.summary.$name)) ('Saved formula cache differs: '+$name)}
}finally{$z.Dispose()}
[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))|Out-Null
$app=$null;$book=$null;$reference=$null
try{
 $app=Open-OwnedSpreadsheet $OutputDirectory;$book=Open-OwnedReportBook $app ([IO.Path]::GetFullPath($File));Set-OwnedSpreadsheetBackground $app
 Assert ($book.FileFormat -eq 51 -and $app.Calculation -eq -4105) 'XLSX format or automatic calculation changed'
 foreach($p in $expected.summary.PSObject.Properties){Assert (Same $book.Worksheets.Item(1).Range($p.Name).Value2 $p.Value) ('Reopened summary differs: '+$p.Name)}
 foreach($entry in @(@(2,'samples',16),@(3,'dq',17))){$values=$expected.($entry[1]);$block=$book.Worksheets.Item($entry[0]).Range('A2').Resize($values.Count,$entry[2]).Value2;for($i=0;$i -lt $values.Count;$i++){for($j=0;$j -lt $entry[2];$j++){Assert (Same $block.GetValue($i+1,$j+1) $values[$i][$j]) ('Reopened cell differs: '+$entry[1]+'/'+$i+'/'+$j)}}}
 Assert ($book.Worksheets.Item(2).Range('M2').HasFormula -and $book.Worksheets.Item(1).Shapes.Count -eq $expected.pictureCount) 'Editable formula or image missing'
 Assert ($book.Worksheets.Item(1).Range('A1').Characters(1,1).Font.Name -eq ([string][char]0x6977+[char]0x4f53)) 'Chinese font changed'
 Assert ($book.Worksheets.Item(2).Range('C1').Characters(1,2).Font.Name -eq 'Times New Roman') 'Latin font changed'
 if($Baseline){$reference=Open-OwnedReportBook $app ([IO.Path]::GetFullPath($Baseline));$last=$book.Worksheets.Item(5).UsedRange.Rows.Count;for($r=1;$r -le $last;$r++){Assert ([math]::Abs($book.Worksheets.Item(5).Rows.Item($r).RowHeight-$reference.Worksheets.Item(5).Rows.Item($r).RowHeight)-lt 0.1) ('Historical row height changed: '+$r)}}
 'Saved caches, automatic recalculation, reopened bond values, editable formulas, image, fonts and row heights passed'
}finally{if($reference){$reference.Close($false);Release-SpreadsheetCom $reference};Close-OwnedSpreadsheet $app $book}
