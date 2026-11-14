param([ValidateSet('capture','start','hide','cleanup','status')][string]$Mode='status',[string]$RunDirectory,[string]$SettingsFile)
$ErrorActionPreference='Stop';$settings=Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8|ConvertFrom-Json;$roots=@{dm=(Split-Path -Parent $settings.dmExe);dq=(Split-Path -Parent $settings.dqExe)}
function Find-App([string]$kind){@(Get-Process -Name 'DM-Native','CefSharp.BrowserSubprocess','DmUpdater','launcher','*DQ*' -ErrorAction SilentlyContinue|Where-Object {try{$_.Path -and $_.Path.StartsWith($roots[$kind]+'\',[StringComparison]::OrdinalIgnoreCase)}catch{$false}})}
function Identity($p){[ordered]@{pid=$p.Id;started=$p.StartTime.ToUniversalTime().ToString('o');path=$p.Path}}
$policyFile=if($RunDirectory){Join-Path $RunDirectory 'process-ownership.json'}else{$null};$policy=$null;if($policyFile -and (Test-Path -LiteralPath $policyFile)){$policy=Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8|ConvertFrom-Json}
function Save-Policy{[IO.File]::WriteAllText($policyFile,($policy|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
if(($Mode -eq 'capture' -or $Mode -eq 'start') -and -not $policy){
 $policy=[pscustomobject]@{startedAt=[DateTime]::UtcNow.ToString('o');dm=$null;dq=$null;wpsBefore=@(Get-Process -Name et -ErrorAction SilentlyContinue|ForEach-Object {Identity $_});officeBefore=@(Get-Process -Name et,EXCEL -ErrorAction SilentlyContinue|ForEach-Object {Identity $_})}
 foreach($kind in @('dm','dq')){$before=@(Find-App $kind|ForEach-Object {Identity $_});$policy.$kind=[pscustomobject]@{wasRunning=($before.Count -gt 0);launchedByRun=$false;attempted=$false;before=$before;launcher=$null}};Save-Policy
}
function Owned-App([string]$kind){if(-not $policy -or -not $policy.$kind.launchedByRun -or $policy.$kind.wasRunning){return @()};$start=[DateTime]::Parse($policy.startedAt).ToUniversalTime().AddSeconds(-2);@(Find-App $kind|Where-Object {$_.StartTime.ToUniversalTime() -ge $start -and $_.Id -notin @($policy.$kind.before|ForEach-Object pid)})}
function Owned-Office {
 if(-not $RunDirectory){return @()};$entries=@();$journal=Join-Path $RunDirectory 'office-instances.jsonl'
 if(Test-Path -LiteralPath $journal){$entries+=@(Get-Content -LiteralPath $journal -Encoding UTF8|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})}
 $legacy=Join-Path $RunDirectory 'wps-instance.json';if(Test-Path -LiteralPath $legacy){$entries+=Get-Content -LiteralPath $legacy -Raw -Encoding UTF8|ConvertFrom-Json}
 $seen=@{};foreach($worker in $entries){$p=Get-Process -Id $worker.processId -ErrorAction SilentlyContinue;if(-not $p -or $seen.ContainsKey($p.Id)){continue};$seen[$p.Id]=$true
  $recordedStart=if($worker.startTime -is [DateTime]){$worker.startTime.ToUniversalTime()}else{[DateTime]::Parse([string]$worker.startTime).ToUniversalTime()}
  # .NET Framework and modern .NET can round FILETIME by one tick differently.
  if($p.ProcessName -notin @('et','EXCEL') -or [math]::Abs(($p.StartTime.ToUniversalTime()-$recordedStart).TotalMilliseconds) -gt 1){continue}
  if($p.Id -in @($policy.officeBefore|ForEach-Object pid) -or $p.Id -in @($policy.wpsBefore|ForEach-Object pid)){continue}
  if($worker.path -and -not [string]::Equals($p.Path,$worker.path,[StringComparison]::OrdinalIgnoreCase)){continue}
  $p
 }
}
if($Mode -eq 'start'){
 foreach($kind in @('dm','dq')){if($policy.$kind.wasRunning -or $policy.$kind.attempted){continue};if(@(Find-App $kind).Count){$policy.$kind.wasRunning=$true;Save-Policy;continue};$policy.$kind.attempted=$true;Save-Policy;$exe=$settings.($kind+'Exe');$p=Start-Process -FilePath $exe -WorkingDirectory $roots[$kind] -WindowStyle Hidden -PassThru;$policy.$kind.launchedByRun=$true;$policy.$kind.launcher=[pscustomobject]@{pid=$p.Id;path=$exe};Save-Policy}
}
$hidden=@();if($Mode -eq 'start' -or $Mode -eq 'hide'){
 Add-Type -TypeDefinition 'using System;using System.Collections.Generic;using System.Runtime.InteropServices;public static class OwnedWindows{public delegate bool Callback(IntPtr h,IntPtr p);[DllImport("user32.dll")]static extern bool EnumWindows(Callback c,IntPtr p);[DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);[DllImport("user32.dll")]static extern bool ShowWindow(IntPtr h,int cmd);public static void Hide(int[] ids){var owned=new HashSet<int>(ids);EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);if(owned.Contains((int)id))ShowWindow(h,0);return true;},IntPtr.Zero);}}'
 $hidden=@(@(Owned-App 'dm')+@(Owned-App 'dq')|ForEach-Object Id);if($hidden.Count){[OwnedWindows]::Hide([int[]]$hidden)}
}
if($Mode -eq 'cleanup'){
 $targets=@(@(Owned-App 'dm')+@(Owned-App 'dq'));foreach($p in $targets){try{[void]$p.CloseMainWindow()}catch{}};if($targets.Count){Start-Sleep -Seconds 2};for($attempt=0;$attempt -lt 3;$attempt++){foreach($p in @(@(Owned-App 'dm')+@(Owned-App 'dq'))){try{Stop-Process -Id $p.Id -Force}catch{}};if(-not @(@(Owned-App 'dm')+@(Owned-App 'dq')).Count){break};Start-Sleep -Milliseconds 700}
 foreach($p in @(Owned-Office)){try{Stop-Process -Id $p.Id -Force -ErrorAction Stop}catch{}};if(@(Owned-Office).Count){Start-Sleep -Milliseconds 500}
}
$ownedRemaining=@(@(Owned-App 'dm')+@(Owned-App 'dq')+@(Owned-Office)|ForEach-Object {Identity $_});$preserved=@();foreach($kind in @('dm','dq')){if($policy -and $policy.$kind.wasRunning){$preserved+=@(Find-App $kind|ForEach-Object {Identity $_})}}
[ordered]@{mode=$Mode;clean=($ownedRemaining.Count -eq 0);ownedRemaining=$ownedRemaining;preserved=$preserved;hiddenProcessIds=$hidden;policy=$policy}|ConvertTo-Json -Depth 8 -Compress
