$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$good=[pscustomobject]@{sampleId='test-1';code='240201.IB';issuer='Test issuer';guarantor=0;windType='Policy bank';term=1;option=0;green='No';science='No';subordinate='No';issueDate=$null;paymentDate=$null;bookrunner=0}
Assert (@(Get-WindPendingFields @($good)).Count -eq 0) 'Optional blanks or zero values rejected'
$completed=$good.PSObject.Copy();$completed.code='q26111225.IB'
Assert (@(Get-WindPendingFields @($completed)).Count -eq 0) 'Completed unsupported code was treated as an unfinished request'
foreach($code in @($null,'','#N/A','Fetching...')){$row=$good.PSObject.Copy();$row.code=$code;Assert (@(Get-WindPendingFields @($row)).Count -eq 0) 'Optional code blocked complete pricing fields'}
foreach($bad in @('Fetching...','#N/A',-2146826246)){
 $row=$good.PSObject.Copy();$row.issuer=$bad
 Assert (@(Get-WindPendingFields @($row)).Count -gt 0) 'Invalid issuer accepted'
}
$row=$good.PSObject.Copy();$row.guarantor=-2146826281
Assert (@(Get-WindPendingFields @($row)).Count -gt 0) 'Numeric Excel error accepted'
$script:reads=0
$result=Wait-WindRows -ExpectedCount 1 -TimeoutSeconds 2 -PollMilliseconds 50 -ReadRows {
 $script:reads++;$r=$good.PSObject.Copy();if($script:reads -le 3){$r.issuer='Fetching...'};$r
}
Assert ($script:reads -ge 5 -and $result.rows[0].code -eq $good.code) 'Stable pending state accepted prematurely'
foreach($kind in @('pending','error','missing-row')){
 $caught=$false
 try{Wait-WindRows -ExpectedCount 1 -TimeoutSeconds 1 -PollMilliseconds 50 -ReadRows {
  if($kind -ne 'missing-row'){$r=$good.PSObject.Copy();$r.bookrunner=if($kind -eq 'pending'){'Fetching...'}else{'#VALUE!'};$r}
 }|Out-Null}catch{$caught=$_.Exception.Message -match 'Wind data timeout'}
 Assert $caught ('Did not fail safely for '+$kind)
}
Write-Output 'Wind readiness, delayed completion, optional values, Excel errors and timeout checks passed'
$bad=$good.PSObject.Copy();$bad.sampleId='bad';$bad.issuer=0;$bad.windType=0
$partial=Wait-WindRows -ExpectedCount 2 -TimeoutSeconds 1 -PollMilliseconds 50 -AllowPartial -ReadRows {$good;$bad}
Assert ($partial.rows.Count -eq 2 -and -not $partial.rows[0].windFailure -and $partial.rows[1].windFailure -match 'issuer') 'Partial completion discarded good rows or accepted bad fields'
$script:reads=0
$unstable=Wait-WindRows -ExpectedCount 2 -TimeoutSeconds 1 -PollMilliseconds 50 -AllowPartial -ReadRows {$script:reads++;$r=$good.PSObject.Copy();$r.issuer='Changing'+$script:reads;$r;$bad}
Assert ($unstable.rows[0].windFailure -match 'stabilize' -and $unstable.rows[1].windFailure) 'Unstable partial result was accepted'
Write-Output 'Partial Wind completion isolates bad or unstable rows and keeps valid sample IDs'
$dictionary=[ordered]@{};foreach($p in $good.PSObject.Properties){$dictionary[$p.Name]=$p.Value};$dictionary['bookrunner']='Fetching...'
$serialized=Wait-WindRows -ExpectedCount 1 -TimeoutSeconds 1 -PollMilliseconds 50 -AllowPartial -ReadRows {$dictionary}
Assert (($serialized.json|ConvertFrom-Json)[0].windFailure -match 'bookrunner') 'Dictionary failure marker was lost in JSON serialization'
Write-Output 'Dictionary failure markers survive serialization for per-sample DM fallback'
