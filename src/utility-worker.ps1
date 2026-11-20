param([Parameter(Mandatory=$true)][string]$RuntimeRoot)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
while($null -ne ($line=[Console]::ReadLine())){
 $id=$null;$clock=[Diagnostics.Stopwatch]::StartNew()
 try{
  $message=$line|ConvertFrom-Json;$id=$message.id
  $file=switch($message.kind){'policy'{'process-policy.ps1'} 'xlsx'{'xlsx-io.ps1'} default{throw 'Unsupported utility operation'}}
  $values=@{};foreach($p in $message.parameters.PSObject.Properties){$values[$p.Name]=$p.Value}
  $captured=@(& (Join-Path $RuntimeRoot ('src/'+$file)) @values)
  $reply=@{id=$id;ok=$true;output=(($captured|ForEach-Object {[string]$_}) -join [Environment]::NewLine);elapsedMs=$clock.ElapsedMilliseconds;workerPid=$PID}
 }catch{$reply=@{id=$id;ok=$false;error=$_.Exception.Message;elapsedMs=$clock.ElapsedMilliseconds;workerPid=$PID}}
 [Console]::WriteLine(($reply|ConvertTo-Json -Depth 8 -Compress))
}
