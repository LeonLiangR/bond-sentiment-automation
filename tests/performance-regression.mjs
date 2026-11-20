// Run against an existing, private local replay fixture; never make live vendor requests.
import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';
import {checkNativeReport} from '../src/report-plan.mjs';
const [fixture,output]=process.argv.slice(2);
if(!fixture||!output)throw Error('Expected fixture and output directories');
const read=async(base,name)=>JSON.parse((await fs.readFile(path.join(base,name),'utf8')).replace(/^\uFEFF/,''));
const rawName=await fs.access(path.join(output,'dm-native.json')).then(()=>'dm-native.json',()=>'dm-rows.json');
assert.deepEqual(await read(output,rawName),await read(fixture,'dm-rows.json'));
const actual=await read(output,'native-report.json'),previous=await read(fixture,'native-report.json');
function equivalent(a,b,label='snapshot'){
 if(typeof a==='number'&&typeof b==='number'){assert.ok(Math.abs(a-b)<1e-10,label);return;}
 if(a&&b&&typeof a==='object'&&typeof b==='object'){assert.deepEqual(Object.keys(a).sort(),Object.keys(b).sort(),label);for(const key of Object.keys(a))equivalent(a[key],b[key],label+'.'+key);return;}
 assert.equal(a,b,label);
}
equivalent(actual,previous);
checkNativeReport(actual,await read(fixture,'result.json'),await read(fixture,'report-plan.json'));
console.log('DM fields/types and complete native report snapshot match previous Office output; independent financial checks passed');
