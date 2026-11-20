param([ValidateSet('extract','upload','report')][string]$Mode,[string]$File,[string]$InputFile,[string]$OutputFile)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
if(-not ('SentimentXlsx' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Xlsx.cs') -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions,System.Xml}
switch($Mode){
 'extract' {[IO.File]::WriteAllText($OutputFile,[SentimentXlsx]::Extract($File),[Text.UTF8Encoding]::new($false))}
 'upload' {[SentimentXlsx]::Upload($File,$InputFile,$OutputFile)}
 'report' {[SentimentXlsx]::PrepareReport($File,$InputFile,$OutputFile)}
}
