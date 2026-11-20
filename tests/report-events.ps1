$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
Add-Type -TypeDefinition @'
using System;
public class SaveApp { public bool EnableEvents=true,CalculateBeforeSave=true,DisplayAlerts=true; }
public class SaveBook {
 public SaveApp App;public bool Fail,Called,Copied;public int FileFormat=51;
 public void SaveAs(string file,int format){if(App.EnableEvents||App.CalculateBeforeSave||App.DisplayAlerts||format!=51)throw new Exception("Unsafe save settings");Called=true;if(Fail)throw new Exception("Save failed");}
 public void SaveCopyAs(string file){if(App.EnableEvents||App.CalculateBeforeSave||App.DisplayAlerts)throw new Exception("Unsafe save settings");Called=true;Copied=true;if(Fail)throw new Exception("Save failed");}
}
'@
$app=[SaveApp]::new();$book=[SaveBook]::new();$book.App=$app;$key=Office-Key $app;$script:OwnedOffice[$key]=$true
Save-OwnedReportBook $app $book 'test.xlsx'
if(-not $book.Called -or -not $book.Copied -or -not $app.EnableEvents -or -not $app.CalculateBeforeSave){throw 'Save settings not restored'}
$book.FileFormat=0;$book.Copied=$false;Save-OwnedReportBook $app $book 'convert.xlsx';if($book.Copied){throw 'Non-XLSX book was not converted'}
$book.Fail=$true;foreach($format in @(51,0)){$book.FileFormat=$format;$caught=$false;try{Save-OwnedReportBook $app $book 'test.xlsx'}catch{$caught=$true};if(-not $caught -or -not $app.EnableEvents -or -not $app.CalculateBeforeSave){throw 'Failure path did not restore settings'}}
$script:OwnedOffice.Remove($key);$caught=$false;try{Save-OwnedReportBook $app $book 'test.xlsx'}catch{$caught=$true};if(-not $caught){throw 'Unowned application modified'}
'Owned report save event/recalculation suppression, restoration and unowned protection passed'
