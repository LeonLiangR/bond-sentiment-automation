$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
foreach($name in @('26TestA','26TestB')){
 $row=[ordered]@{name=$name;issuer=0;windType=0;term=0}
 Assert ((Get-WindRetryName $row) -eq '26Test') 'Final A/B not removed once'
}
foreach($name in @('26TestC','26Testa','26TestA(Green)','26Test')){
 Assert ($null -eq (Get-WindRetryName ([ordered]@{name=$name;issuer=0}))) 'Unrequested part of name removed'
}
Assert ((Get-WindRetryName ([ordered]@{name='26TestAB';issuer='0'})) -eq '26TestA') 'Removed more than one final letter'
$good=[ordered]@{name='26TestA';issuer='Issuer';windType='Type';term=3;green='No';science='No';subordinate='No';code=0;guarantor=0;option=0;bookrunner=0}
Assert ($null -eq (Get-WindRetryName $good)) 'Legitimate zeros or optional code triggered retry'
$good.issuer='#N/A';Assert ($null -eq (Get-WindRetryName $good)) 'Nonzero error incorrectly stripped name'
$good.issuer='Issuer';$good.green='0';Assert ((Get-WindRetryName $good) -eq '26Test') 'Invalid zero flag did not trigger retry'
'Wind final-A/B retry selection and valid-zero protection passed'
