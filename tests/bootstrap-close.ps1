$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
Add-Type -TypeDefinition @'
using System;using System.Collections.Generic;
public class CloseApp {public bool DisplayAlerts=true,EnableEvents=true;public CloseBooks Workbooks=new CloseBooks();public int QuitCount;public void Quit(){if(DisplayAlerts||Workbooks.Count>0)throw new Exception("Save prompt");QuitCount++;}}
public class CloseBooks {public List<CloseBook> Rows=new List<CloseBook>();public int Count{get{int n=0;foreach(var b in Rows)if(!b.Closed)n++;return n;}}public CloseBook Item(int i){foreach(var b in Rows)if(!b.Closed&&--i==0)return b;throw new Exception("Missing book");}}
public class CloseBook {public CloseApp App;public string FullName;public bool Saved,Closed,Fail;public void Close(bool save){if(App.DisplayAlerts||App.EnableEvents||!Saved||save)throw new Exception("Save prompt or cancel event");if(Fail)throw new Exception("Close failed");Closed=true;App.DisplayAlerts=true;}}
'@
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Book($app,$name){$b=New-Object CloseBook;$b.App=$app;$b.FullName=$name;$app.Workbooks.Rows.Add($b);return $b}
$app=New-Object CloseApp;$key=Office-Key $app;$script:OwnedOffice[$key]=$true
$file=Join-Path ([IO.Path]::GetTempPath()) ('sentiment-bootstrap-test-'+[guid]::NewGuid().ToString('N')+'.csv');[IO.File]::WriteAllText($file,'test')
try{
 $bootstrap=Book $app $file;$business=Book $app 'business.xlsx';$script:ExcelBootstrapFiles[$key]=$file
 Close-OwnedBootstrap $app
 Assert ($bootstrap.Closed -and -not $business.Closed -and $app.Workbooks.Count -eq 1 -and $app.EnableEvents -and -not(Test-Path -LiteralPath $file)) 'Bootstrap not discarded independently or events not restored'
 $extra=Book $app 'addin-dirty.xlsx';Close-OwnedSpreadsheet $app $null
 Assert ($business.Closed -and $extra.Closed -and $app.EnableEvents -and $app.QuitCount -eq 1) 'Remaining owned workbooks prompted on quit'
 $existing=New-Object CloseApp;$old=Book $existing 'user.xlsx';$script:ExcelBootstrapFiles[(Office-Key $existing)]='user.xlsx';Close-OwnedBootstrap $existing;Close-OwnedSpreadsheet $existing $old
 Assert (-not $old.Closed -and $existing.DisplayAlerts -and $existing.EnableEvents -and $existing.QuitCount -eq 0) 'Unowned workbook changed'
 $broken=New-Object CloseApp;$b=Book $broken 'broken.xlsx';$b.Fail=$true;$caught=$false
 try{Close-SpreadsheetBookWithoutSaving $broken $b}catch{$caught=$true}
 Assert ($caught -and $broken.EnableEvents) 'Close failure did not restore events'
 Write-Output 'Bootstrap close, dirty remaining workbook cleanup, existing instance protection and event restoration passed (simulation)'
}finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
