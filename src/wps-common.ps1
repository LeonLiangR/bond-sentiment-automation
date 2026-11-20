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
# Excel names AND CLSIDs can be redirected. Excel uses a verified executable and
# the native object model of its exact new process; WPS activation is unchanged.
function New-SpreadsheetProgId([string]$ProgId){return New-Object -ComObject $ProgId}
function New-SpreadsheetCom([string]$ProgId,[string]$TrackerDirectory){
 if([string]::Equals($ProgId,'Excel.Application',[StringComparison]::OrdinalIgnoreCase)){
  return New-ExcelDirect (Get-SpreadsheetSpec) $TrackerDirectory
 }
 return New-SpreadsheetProgId $ProgId
}
function Initialize-ExcelNative {
 if('SentimentExcelNative' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Threading;
public static class SentimentExcelNative {
 delegate bool Callback(IntPtr hwnd, IntPtr arg);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback,IntPtr arg);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent,Callback callback,IntPtr arg);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder name,int count);
 [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd,int command);
 [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hwnd,int command);
 [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int cx,int cy,uint flags);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,UIntPtr wParam,IntPtr lParam,uint flags,uint timeout,out UIntPtr result);
 [DllImport("oleacc.dll",PreserveSig=true)] static extern int AccessibleObjectFromWindow(IntPtr hwnd,uint objectId,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out object result);
 static bool Own(IntPtr h,int pid){uint owner;GetWindowThreadProcessId(h,out owner);return owner==(uint)pid;}
 static string Class(IntPtr h){var text=new StringBuilder(256);GetClassName(h,text,text.Capacity);return text.ToString();}
 public static IntPtr[] Windows(int pid){
  var list=new List<IntPtr>();
  EnumWindows(delegate(IntPtr root,IntPtr arg){if(Own(root,pid))EnumChildWindows(root,delegate(IntPtr child,IntPtr unused){if(Own(child,pid)&&Class(child)=="EXCEL7")list.Add(child);return true;},IntPtr.Zero);return true;},IntPtr.Zero);
  return list.ToArray();
 }
 public static void Hide(int pid){EnumWindows(delegate(IntPtr h,IntPtr unused){if(Own(h,pid))ShowWindow(h,0);return true;},IntPtr.Zero);}
 public sealed class BackgroundGuard : IDisposable {
  readonly Process process;readonly long started;Timer timer;int busy;int disposed;
  public BackgroundGuard(int pid){process=Process.GetProcessById(pid);started=process.StartTime.ToUniversalTime().Ticks;timer=new Timer(Tick,null,0,25);}
  void Tick(object unused){if(Interlocked.Exchange(ref busy,1)!=0)return;try{
   if(Volatile.Read(ref disposed)!=0)return;process.Refresh();
   if(process.HasExited||process.StartTime.ToUniversalTime().Ticks!=started){Dispose();return;}
   EnumWindows(delegate(IntPtr h,IntPtr arg){if(Own(h,process.Id)){
    // SDI Excel can create/show a fresh top-level window on every workbook open.
    // Move it off screen as well as hiding it, without activating another window.
    SetWindowPos(h,IntPtr.Zero,-32000,-32000,0,0,0x4000|0x10|0x4|0x1);
    ShowWindowAsync(h,0);
   }return true;},IntPtr.Zero);
  }catch{Dispose();}finally{Volatile.Write(ref busy,0);}}
  public void Dispose(){if(Interlocked.Exchange(ref disposed,1)==0&&timer!=null)timer.Dispose();}
 }
 public static BackgroundGuard Guard(int pid){return new BackgroundGuard(pid);}
 public static object Read(IntPtr hwnd,int pid){
  if(!Own(hwnd,pid)||Class(hwnd)!="EXCEL7")throw new InvalidOperationException("Excel native window identity changed");
  UIntPtr response;if(SendMessageTimeout(hwnd,0,UIntPtr.Zero,IntPtr.Zero,3,500,out response)==IntPtr.Zero)return null;
  object value;Guid iid=new Guid("00020400-0000-0000-C000-000000000046");
  int hr=AccessibleObjectFromWindow(hwnd,0xfffffff0,ref iid,out value);
  if(hr<0)Marshal.ThrowExceptionForHR(hr);return value;
 }
}
'@
}
function Start-ExcelProcess([string]$Exe,[string]$Bootstrap){
 # Explicit /x creates a separate process. The neutral CSV guarantees an EXCEL7
 # document window without depending on file associations, templates or macros.
 return Start-Process -FilePath $Exe -ArgumentList @('/x',('"'+$Bootstrap+'"')) -WorkingDirectory (Split-Path -Parent $Exe) -WindowStyle Hidden -PassThru
}
function Get-ExcelNativeWindows([int]$ProcessId){Initialize-ExcelNative;return [SentimentExcelNative]::Windows($ProcessId)}
function Read-ExcelNativeWindow([IntPtr]$Handle,[int]$ProcessId){return [SentimentExcelNative]::Read($Handle,$ProcessId)}
function Hide-ExcelWindows([int]$ProcessId){[SentimentExcelNative]::Hide($ProcessId)}
function Write-OfficeActivation([string]$Directory,$Process,[string]$Engine,[string]$Method){
 if(-not $Directory){return}
 $record=[ordered]@{engine=$Engine;processName=$Process.ProcessName;processId=$Process.Id;startTime=$Process.StartTime.ToUniversalTime().ToString('o');path=$Process.Path;activationOnly=$true;activationMethod=$Method}
 [IO.File]::AppendAllText((Join-Path $Directory 'office-instances.jsonl'),(($record|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
}
function Test-ExcelProcessIdentity($Process,$Spec,$Before,[DateTime]$Started){
 $Process.Refresh()
 return -not $Process.HasExited -and $Process.Id -notin $Before -and $Process.ProcessName -ieq 'EXCEL' -and [string]::Equals($Process.Path,$Spec.exe,[StringComparison]::OrdinalIgnoreCase) -and [math]::Abs(($Process.StartTime.ToUniversalTime()-$Started).TotalMilliseconds) -le 1
}
function New-ExcelDirect($Spec,[string]$TrackerDirectory,[ValidateRange(1,120)][int]$TimeoutSeconds=45){
 if(-not $Spec.exe -or -not (Test-Path -LiteralPath $Spec.exe -PathType Leaf) -or [IO.Path]::GetFileName($Spec.exe) -ine 'EXCEL.EXE'){throw 'Excel executable is missing or invalid; select Microsoft Office EXCEL.EXE in settings'}
 $before=@(Get-SpreadsheetProcesses|ForEach-Object Id);$process=$null;$started=[DateTime]::MinValue;$bootstrap=$null;$bound=$false;$guard=$null
 try{
  Initialize-ExcelNative
  $directory=if($TrackerDirectory){Join-Path $TrackerDirectory 'office-bootstrap'}else{Join-Path ([IO.Path]::GetTempPath()) 'BondSentimentOffice'}
  [IO.Directory]::CreateDirectory($directory)|Out-Null;$bootstrap=Join-Path $directory ('bootstrap-'+[guid]::NewGuid().ToString('N')+'.csv')
  [IO.File]::WriteAllText($bootstrap,"Sentiment automation bootstrap`r`n",[Text.Encoding]::ASCII)
  $process=Start-ExcelProcess $Spec.exe $bootstrap;$started=$process.StartTime.ToUniversalTime()
  if(-not (Test-ExcelProcessIdentity $process $Spec $before $started)){throw 'Excel direct launch did not return the selected new EXCEL process'}
  # Register ownership BEFORE any native/COM binding, so cancellation can clean up.
  Write-OfficeActivation $TrackerDirectory $process 'excel' 'direct-exe-nativeom'
  $guard=[SentimentExcelNative]::Guard($process.Id)
  $clock=[Diagnostics.Stopwatch]::StartNew();$last='EXCEL7 document window is not ready'
  while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
   if(-not (Test-ExcelProcessIdentity $process $Spec $before $started)){throw 'The launched Excel process exited or its identity changed'}
   Hide-ExcelWindows $process.Id
   foreach($handle in @(Get-ExcelNativeWindows $process.Id)){
    $window=$null;$candidate=$null
    try{
     $window=Read-ExcelNativeWindow $handle $process.Id
     if($null -eq $window){continue}
     $candidate=$window.Application
     $actual=Get-SpreadsheetProcess $candidate
     if($actual.Id -ne $process.Id -or $actual.Id -in $before -or $actual.ProcessName -ine 'EXCEL' -or -not [string]::Equals($actual.Path,$Spec.exe,[StringComparison]::OrdinalIgnoreCase)){throw [InvalidOperationException]::new('Excel native object belongs to a different or pre-existing process')}
     $script:ExcelBackgroundGuards[(Office-Key $candidate)]=$guard
     $script:ExcelBootstrapFiles[(Office-Key $candidate)]=$bootstrap
     $bound=$true;return $candidate
    }catch{
     if($_.Exception.Message -match 'different or pre-existing process'){throw}
     $last=$_.Exception.Message
    }finally{if(-not $bound){Release-SpreadsheetCom $candidate};Release-SpreadsheetCom $window}
   }
   Start-Sleep -Milliseconds 500
  }
  throw ('Excel direct-launch binding timed out after '+$TimeoutSeconds+'s: '+$last)
 }catch{
  if($process -and $started -ne [DateTime]::MinValue){try{if(Test-ExcelProcessIdentity $process $Spec $before $started){Stop-Process -Id $process.Id -Force -ErrorAction Stop}}catch{}}
  throw
 }finally{if(-not $bound){if($guard){$guard.Dispose()};if($bootstrap){Remove-Item -LiteralPath $bootstrap -Force -ErrorAction SilentlyContinue}}}
}
$script:ExcelBackgroundGuards=@{}
$script:ExcelBootstrapFiles=@{}
function Close-OwnedBootstrap($Application){
 $key=Office-Key $Application
 if(-not $script:OwnedOffice.ContainsKey($key) -or -not $script:ExcelBootstrapFiles.ContainsKey($key)){return}
 $file=$script:ExcelBootstrapFiles[$key];$books=$null;$book=$null
 try{
  $Application.DisplayAlerts=$false;$books=$Application.Workbooks
  for($i=$books.Count;$i -ge 1;$i--){
   try{$book=$books.Item($i)
    if([string]::Equals([string]$book.FullName,$file,[StringComparison]::OrdinalIgnoreCase)){
     Close-SpreadsheetBookWithoutSaving $Application $book
    }
   }finally{Release-SpreadsheetCom $book;$book=$null}
  }
  $script:ExcelBootstrapFiles.Remove($key)
  Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
 }finally{Release-SpreadsheetCom $books}
}
function Close-SpreadsheetBookWithoutSaving($Application,$Book){
 # Prevent workbook BeforeClose handlers from cancelling this internal close.
 # Restore events immediately; Wind worksheet events remain enabled in normal work.
 $events=$Application.EnableEvents
 try{$Application.DisplayAlerts=$false;$Application.EnableEvents=$false;$Book.Saved=$true;$Book.Close($false)}
 finally{$Application.EnableEvents=$events}
}
function Close-AllOwnedSpreadsheetBooks($Application){
 if(-not $script:OwnedOffice.ContainsKey((Office-Key $Application))){return}
 $books=$null;$book=$null
 try{
  $Application.DisplayAlerts=$false;$books=$Application.Workbooks
  for($i=$books.Count;$i -ge 1;$i--){try{$book=$books.Item($i);Close-SpreadsheetBookWithoutSaving $Application $book}finally{Release-SpreadsheetCom $book;$book=$null}}
 }finally{Release-SpreadsheetCom $books}
}
function Stop-ExcelBackgroundGuard($Application){
 if($null -eq $Application){return};$key=Office-Key $Application
 if($script:ExcelBackgroundGuards.ContainsKey($key)){$script:ExcelBackgroundGuards[$key].Dispose();$script:ExcelBackgroundGuards.Remove($key)}
}
function Set-OwnedSpreadsheetBackground($Application){
 if($null -eq $Application -or -not $script:OwnedOffice.ContainsKey((Office-Key $Application))){return}
 Invoke-SpreadsheetReady {$Application.Visible=$false;$Application.DisplayAlerts=$false}
 if((Get-SpreadsheetSpec).engine -eq 'excel'){
  Invoke-SpreadsheetReady {$Application.ScreenUpdating=$false;$Application.Interactive=$false}
  $p=Get-SpreadsheetProcess $Application;Hide-ExcelWindows $p.Id
 }
}
function Get-SpreadsheetProcesses {return @(Get-Process -Name et,EXCEL -ErrorAction SilentlyContinue)}
function Get-SpreadsheetProcess($Application){[uint32]$instanceId=0;[void][SentimentOfficeWindow]::GetWindowThreadProcessId([IntPtr]([long]$Application.Hwnd),[ref]$instanceId);if(-not $instanceId){throw 'Spreadsheet instance has no process identity'};return Get-Process -Id $instanceId}
function Release-SpreadsheetCom($Object){if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object)}}
function Office-Key($Application){return [string][Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Application)}
function Test-SpreadsheetBusy($Failure){
 $exception=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception}else{$Failure}
 while($null -ne $exception){if($exception.HResult -in @(-2147418111,-2147417846)){return $true};$exception=$exception.InnerException}
 return $false
}
function Invoke-SpreadsheetReady([scriptblock]$Operation,[int]$Attempts=5){
 for($attempt=1;$attempt -le $Attempts;$attempt++){
  try{return (& $Operation)}catch{if(-not (Test-SpreadsheetBusy $_) -or $attempt -eq $Attempts){throw};Start-Sleep -Milliseconds ([int][math]::Min(4000,1000*$attempt))}
 }
}
function Register-ActivationProcesses($Spec,$Before,[DateTime]$Started,[string]$TrackerDirectory){
 if(-not $TrackerDirectory -or -not $Spec.exe){return}
 # A direct child of this worker with the exact selected executable is provably ours.
 # Time alone is insufficient: never claim another user's newly opened application.
 foreach($candidate in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$PID) -ErrorAction SilentlyContinue)){
  if($candidate.ParentProcessId -ne $PID -or $candidate.ProcessId -in $Before -or -not [string]::Equals($candidate.ExecutablePath,$Spec.exe,[StringComparison]::OrdinalIgnoreCase) -or -not $candidate.CreationDate -or $candidate.CreationDate.ToUniversalTime() -lt $Started){continue}
  try{$p=Get-Process -Id $candidate.ProcessId -ErrorAction Stop;$time=$p.StartTime;if(-not $time){continue};$info=[ordered]@{engine=$Spec.engine;processName=$p.ProcessName;processId=$p.Id;startTime=$time.ToUniversalTime().ToString('o');path=$p.Path;activationOnly=$true};[IO.File]::AppendAllText((Join-Path $TrackerDirectory 'office-instances.jsonl'),(($info|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))}catch{}
 }
}
function Open-OwnedSpreadsheet([string]$TrackerDirectory){
 $spec=Get-SpreadsheetSpec;$before=@(Get-SpreadsheetProcesses|ForEach-Object Id);$application=$null;$owned=$false;$activationStarted=[DateTime]::UtcNow
 try{
  try{if($spec.engine -eq 'excel'){$application=New-SpreadsheetCom $spec.progId $TrackerDirectory}else{$application=Invoke-SpreadsheetReady {try{New-SpreadsheetCom $spec.progId $TrackerDirectory}catch{Register-ActivationProcesses $spec $before $activationStarted $TrackerDirectory;throw}}}}catch{if(Test-SpreadsheetBusy $_){throw ($spec.name+' is busy and rejected automation after bounded retries (RPC_E_CALL_REJECTED). Retry later; existing workbooks were preserved. '+$_.Exception.Message)};$hint=if($spec.engine -eq 'excel'){'Excel automation is unavailable. Direct EXCEL.EXE launch and process-bound native object retrieval failed. '}else{$spec.name+' automation is unavailable. Check installation and COM registration. '};throw ($hint+$_.Exception.Message)}
  $process=Invoke-SpreadsheetReady {Get-SpreadsheetProcess $application}
  if($process.Id -in $before){throw 'Automation returned a pre-existing spreadsheet instance; it will not be modified or closed'}
  if($process.ProcessName -notin @('et','EXCEL')){throw 'Unexpected spreadsheet process; it will not be modified or closed'}
  $key=Office-Key $application;$script:OwnedOffice[$key]=$true;$owned=$true
  $info=[ordered]@{engine=$spec.engine;processName=$process.ProcessName;processId=$process.Id;startTime=$process.StartTime.ToUniversalTime().ToString('o');path=$process.Path}
  if($TrackerDirectory){[IO.File]::AppendAllText((Join-Path $TrackerDirectory 'office-instances.jsonl'),(($info|ConvertTo-Json -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))}
  if($process.ProcessName -ine $spec.processName){throw ('Requested '+$spec.name+' but COM returned '+$process.ProcessName+'; no fallback is allowed. The selected COM class is registered to another application; check its registration. Existing applications were preserved.')}
  if($spec.exe -and -not [string]::Equals($process.Path,$spec.exe,[StringComparison]::OrdinalIgnoreCase)){throw ($spec.name+' COM registration points to a different executable; check software paths')}
  Set-OwnedSpreadsheetBackground $application
  if($spec.engine -eq 'excel'){Invoke-SpreadsheetReady {Close-OwnedBootstrap $application}}
  return $application
 }catch{
  Register-ActivationProcesses $spec $before $activationStarted $TrackerDirectory
  if($owned){try{Close-AllOwnedSpreadsheetBooks $application}catch{};try{$application.DisplayAlerts=$false;$application.Quit()}catch{};$script:OwnedOffice.Remove((Office-Key $application))}
  if($application){$script:ExcelBootstrapFiles.Remove((Office-Key $application))}
  Stop-ExcelBackgroundGuard $application;Release-SpreadsheetCom $application;throw
 }
}
function Open-OwnedWps([string]$TrackerDirectory){return Open-OwnedSpreadsheet $TrackerDirectory}
function Open-OwnedReportBook($Application,[string]$File){
 if(-not $script:OwnedOffice.ContainsKey((Office-Key $Application))){throw 'Report opening requires an owned Office instance'}
 $events=$Application.EnableEvents
 try{$Application.EnableEvents=$false;return $Application.Workbooks.Open($File,0,$false)}finally{$Application.EnableEvents=$events}
}
function Save-OwnedReportBook($Application,$Book,[string]$File){
 if(-not $script:OwnedOffice.ContainsKey((Office-Key $Application))){throw 'Report saving requires an owned Office instance'}
 $events=$Application.EnableEvents;$hasCalculateBeforeSave=$false;$calculateBeforeSave=$null
 try{$calculateBeforeSave=$Application.CalculateBeforeSave;$Application.CalculateBeforeSave=$false;$hasCalculateBeforeSave=$true}catch{}
 try{
  $Application.DisplayAlerts=$false;$Application.EnableEvents=$false
  $format=0;try{$format=[int]$Book.FileFormat}catch{}
  # Prepared reports are already XLSX. SaveCopyAs avoids an unnecessary format
  # conversion and leaves the working template untouched; other formats convert.
  if($format -eq 51){$Book.SaveCopyAs($File)}else{$Book.SaveAs($File,51)}
 }
 finally{$Application.EnableEvents=$events;if($hasCalculateBeforeSave){$Application.CalculateBeforeSave=$calculateBeforeSave}}
}
function Get-WindRetryName($Row){
 $name=([string]$Row.name).Trim();if($name -cnotmatch '[AB]$'){return $null}
 # Zero is valid for option and guarantor; a reference code alone is not a gate.
 foreach($key in @('issuer','windType','term','green','science','subordinate')){
  $value=$Row.$key;if($null -ne $value -and ([string]$value).Trim() -eq '0'){return $name.Substring(0,$name.Length-1)}
 }
 return $null
}
function Get-WindPendingFields($Rows){
 foreach($row in $Rows){
  foreach($key in @('issuer','guarantor','windType','term','option','green','science','subordinate','issueDate','paymentDate','bookrunner')){
   $value=$row.$key;$text=([string]$value).Trim()
   # Excel Value2 exposes VT_ERROR cells as signed HRESULT numbers, not just # text.
   $excelError=$value -is [System.Runtime.InteropServices.ErrorWrapper] -or ($value -is [ValueType] -and $value -isnot [bool] -and [double]$value -ge -2146826288 -and [double]$value -le -2146826245)
   # DQ-ready terms determine readiness; the optional reference code is not a gate.
   if($excelError -or $text -match '^(?i:Fetching|Loading|Pending|#)' -or ($key -in @('issuer','windType') -and ($value -isnot [string] -or $text -eq '0')) -or ($key -in @('term','green','science','subordinate') -and $text -eq '0') -or ($key -in @('issuer','windType','term','option','green','science','subordinate') -and ($null -eq $value -or $text -eq ''))){
    '{0}/{1}: {2}' -f $row.sampleId,$key,$text
   }
  }
 }
}
function Complete-WindRead($Rows,$States,[double]$Elapsed,$EarlyIds=@()){
 $output=@(foreach($row in $Rows){$issues=@(Get-WindPendingFields @($row));if($States[[string]$row.sampleId].count -lt 2){$issues+='Results did not stabilize'};if($issues.Count){$message='Wind未取得有效条款：'+($issues -join '; ');if($row -is [Collections.IDictionary]){$row['windFailure']=$message}else{$row|Add-Member -NotePropertyName windFailure -NotePropertyValue $message -Force}};$row})
 return [pscustomobject]@{rows=$output;json=(ConvertTo-Json -InputObject $output -Depth 8);stable=$false;partial=$true;earlyRetryIds=@($EarlyIds);elapsedSeconds=$Elapsed}
}
function Join-WindNameRetryRows($OriginalRows,$RetryRows,$RetrySamples){
 $retryMap=@{};foreach($row in $RetryRows){$retryMap[[string]$row.sampleId]=$row}
 $sampleMap=@{};foreach($sample in $RetrySamples){$sampleMap[[string]$sample.sampleId]=$sample}
 foreach($original in $OriginalRows){$key=[string]$original.sampleId;$sample=$sampleMap[$key]
  if(-not $sample){$original;continue}
  if(@(Get-WindPendingFields @($original)).Count -eq 0 -and -not(Get-WindRetryName $original)){$original;continue}
  $retry=$retryMap[$key];if(-not $retry -or $retry.name -cne $sample.name -or $original.name -cne $sample.name){throw 'Wind retry identity changed'}
  $metadata=[ordered]@{originalName=$sample.name;queryName=$sample.query;previousFailure=(@(Get-WindPendingFields @($original)) -join '; ');returnedValid=(@(Get-WindPendingFields @($retry)).Count -eq 0)}
  if($retry -is [Collections.IDictionary]){$retry['windRetry']=$metadata}else{$retry|Add-Member -NotePropertyName windRetry -NotePropertyValue $metadata -Force};$retry
 }
}
function Wait-WindRows([scriptblock]$ReadRows,[int]$ExpectedCount,[ValidateRange(1,240)][int]$TimeoutSeconds=120,[ValidateRange(50,5000)][int]$PollMilliseconds=1000,[switch]$AllowPartial,[ValidateRange(0,120)][double]$EarlyRetrySeconds=0,[scriptblock]$OnEarlyRetry){
 $clock=[Diagnostics.Stopwatch]::StartNew();$previous='';$readyBefore=$false;$problems=@();$rowState=@{};$rows=@();$notified=@{}
 while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
  $rows=@(& $ReadRows);$problems=@(Get-WindPendingFields $rows)
  foreach($row in $rows){$key=[string]$row.sampleId;$signature=ConvertTo-Json -InputObject $row -Depth 8 -Compress;$state=$rowState[$key];$same=$state -and $state.signature -eq $signature;$count=if($same){$state.count+1}else{1};$since=if($same){$state.since}else{$clock.Elapsed.TotalSeconds};$rowState[$key]=@{signature=$signature;count=$count;since=$since}}
  if($rows.Count -ne $ExpectedCount){$problems+='Unexpected row count'}
  $json=ConvertTo-Json -InputObject @($rows) -Depth 5
  $ready=$rows.Count -gt 0 -and $problems.Count -eq 0
  if($ready -and $readyBefore -and $json -eq $previous){return [pscustomobject]@{rows=$rows;json=$json;stable=$true;elapsedSeconds=$clock.Elapsed.TotalSeconds}}
  if($AllowPartial -and $EarlyRetrySeconds -gt 0 -and $rows.Count -eq $ExpectedCount -and @($rows|ForEach-Object sampleId|Select-Object -Unique).Count -eq $ExpectedCount){
   $early=@(foreach($row in $rows){$state=$rowState[[string]$row.sampleId];if(-not $notified.ContainsKey([string]$row.sampleId) -and (Get-WindRetryName $row) -and $state.count -ge 2 -and ($clock.Elapsed.TotalSeconds-$state.since) -ge $EarlyRetrySeconds -and -not(@(Get-WindPendingFields @($row)) -match 'Fetching|Loading|Pending|#')){$row.sampleId}})
   if($early.Count){if($OnEarlyRetry){foreach($id in $early){$notified[[string]$id]=$true};& $OnEarlyRetry $rows $early;$readyBefore=$false;$previous='';continue}else{return Complete-WindRead $rows $rowState $clock.Elapsed.TotalSeconds $early}}
  }
  $readyBefore=$ready;$previous=$json
  Start-Sleep -Milliseconds $PollMilliseconds
 }
 if($AllowPartial -and $rows.Count -eq $ExpectedCount -and @($rows|ForEach-Object sampleId|Select-Object -Unique).Count -eq $ExpectedCount){
  return Complete-WindRead $rows $rowState $clock.Elapsed.TotalSeconds
 }
 if(-not $problems.Count){$problems=@('Results did not stabilize')}
 throw ('Wind data timeout after '+$TimeoutSeconds+'s; pending or invalid fields: '+(($problems|Select-Object -First 8) -join '; '))
}
function Matrix($Rows){$count=$Rows.Count;$cols=$Rows[0].Count;$matrix=New-Object 'object[,]' $count,$cols;for($i=0;$i -lt $count;$i++){for($j=0;$j -lt $cols;$j++){$matrix[$i,$j]=$Rows[$i][$j]}};return ,$matrix}
function Write-Block($Sheet,[string]$Cell,$Rows,[bool]$Formula=$false){if(-not $Rows -or -not $Rows.Count){return};$range=$Sheet.Range($Cell).Resize($Rows.Count,$Rows[0].Count);$matrix=Matrix $Rows;if($Formula){$range.Formula=$matrix}else{$range.Value2=$matrix}}
function Close-OwnedSpreadsheet($Application,$Book){
 $owned=$null -ne $Application -and $script:OwnedOffice.ContainsKey((Office-Key $Application))
 if($owned){
  if($null -ne $Book){try{Close-SpreadsheetBookWithoutSaving $Application $Book}catch{}}
  try{Close-AllOwnedSpreadsheetBooks $Application}catch{}
  try{$Application.DisplayAlerts=$false;$Application.Quit()}catch{}
  $script:OwnedOffice.Remove((Office-Key $Application));$script:ExcelBootstrapFiles.Remove((Office-Key $Application))
 }
 Stop-ExcelBackgroundGuard $Application;Release-SpreadsheetCom $Book;Release-SpreadsheetCom $Application;[GC]::Collect();[GC]::WaitForPendingFinalizers()
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
