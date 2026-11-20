param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
Add-Type -Path (Join-Path $PSScriptRoot '../src/Xlsx.cs') -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions,System.Xml
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$file=Join-Path $OutputDirectory 'sparse-dm.xlsx'
$z=[IO.Compression.ZipFile]::Open($file,[IO.Compression.ZipArchiveMode]::Create)
function Part($Name,$Xml){$w=[IO.StreamWriter]::new($z.CreateEntry($Name).Open(),[Text.UTF8Encoding]::new($false));try{$w.Write($Xml)}finally{$w.Dispose()}}
try{
 Part 'xl/workbook.xml' '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="DM" sheetId="1" r:id="r1"/></sheets></workbook>'
 Part 'xl/_rels/workbook.xml.rels' '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Target="data/raw.xml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/></Relationships>'
 # Split shared string runs, escaped literal tokens, formula caches, sparse columns.
 $header=[string][char]0x503A+[char]0x5238+[char]0x7B80+[char]0x79F0
 Part 'xl/sharedStrings.xml' ('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><r><t>'+ $header.Substring(0,2)+'</t></r><r><t>'+$header.Substring(2)+'</t></r></si></sst>')
 Part 'xl/data/raw.xml' '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="2"><c r="A2" t="inlineStr"><is><t>11-13</t></is></c></row><row r="4"><c r="A4" t="s"><v>0</v></c><c r="B4" t="inlineStr"><is><t>type</t></is></c><c r="G4" t="inlineStr"><is><t>coupon</t></is></c></row><row r="5"><c r="A5" t="inlineStr"><is><t>0012_x005F_x000b_</t></is></c><c r="B5" t="inlineStr"><is><t>MTN</t></is></c><c r="C5" t="inlineStr"><is><t>=1+1</t></is></c><c r="D5" t="inlineStr"><is><t>3.13</t></is></c><c r="E5" t="b"><v>1</v></c><c r="G5"><f>1/100</f><v>0.01</v></c></row><row r="7"><c r="A7" t="inlineStr"><is><t>ignored incomplete row</t></is></c></row></sheetData></worksheet>'
}finally{$z.Dispose()}
$data=[SentimentXlsx]::Extract($file)|ConvertFrom-Json
if($data.headerRow -ne 4 -or $data.rows.Count -ne 1 -or $data.rows[0].row -ne 5){throw 'Sparse rows or shared header incorrect'}
$values=$data.rows[0].values
if($values[0] -cne '0012_x000b_' -or $values[2] -cne '=1+1' -or $values[3] -isnot [string] -or $values[3] -cne '3.13' -or $values[4] -ne $true -or $null -ne $values[5] -or $values[6] -ne 0.01){throw 'Typed values, escapes, blanks or formula cache changed'}
'Sparse XLSX relationships, rich shared header, types, literal escape tokens and cached formulas passed'
