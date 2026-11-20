$ErrorActionPreference='Stop'
$file=Join-Path $PSScriptRoot '../src/process-policy.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Identity','Owned-App')){$function=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object Name -eq $name;. ([scriptblock]::Create($function.Extent.Text))}
Add-Type -TypeDefinition 'public class TestProcess {public int Id=42; public string Path="C:\\TestApp\\app.exe"; public System.DateTime? StartTime=System.DateTime.UtcNow;public bool HasExited=false;public void Refresh(){} }'
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$p=New-Object TestProcess
Assert ((Identity $p).pid -eq 42) 'Valid identity missing'
$p.StartTime=$null;Assert ($null -eq (Identity $p)) 'Null start time accepted'
$p.StartTime=[DateTime]::UtcNow;$p.HasExited=$true;Assert ($null -eq (Identity $p)) 'Exited process accepted'
Assert ($null -eq (Identity $null)) 'Null process accepted'
$p.HasExited=$false;$p.StartTime=$null
$good=New-Object TestProcess;$good.Id=43
function Find-App($kind){@($p,$good)}
$policy=[pscustomobject]@{startedAt=[DateTime]::UtcNow.AddSeconds(-3).ToString('o');dm=[pscustomobject]@{launchedByRun=$true;wasRunning=$false;before=@()}}
$owned=@(Owned-App 'dm');Assert ($owned.Count -eq 1 -and $owned[0].Id -eq 43) 'Invalid process prevented valid cleanup selection'
$policy.dm.wasRunning=$true;Assert (@(Owned-App 'dm').Count -eq 0) 'Pre-existing application became owned'
$policy.dm.wasRunning=$false;$policy.dm.before=@(@{pid=43});Assert (@(Owned-App 'dm').Count -eq 0) 'Protected PID became owned'
Write-Output 'Process identity regression passed: null time, exited process, valid survivor and pre-existing protection'
