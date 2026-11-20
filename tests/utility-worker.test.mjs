import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import path from'node:path';import os from'node:os';import {fileURLToPath}from'node:url';
import {PowerShellUtility}from'../src/utility-worker.mjs';
test('utility reuses its process/compiler, preserves typed XLSX values, survives operation errors and exits', {skip:process.platform!=='win32',timeout:60000},async()=>{
 const root=fileURLToPath(new URL('..',import.meta.url)),dir=await fs.mkdtemp(path.join(os.tmpdir(),'sentiment-utility-')),worker=new PowerShellUtility(root);
 try{
  const settings=path.join(dir,'settings.json');await fs.writeFile(settings,JSON.stringify({dmExe:'C:\\NoDM\\DM-Native.exe',dqExe:'C:\\NoDQ\\DQ.exe'}));
  const args={RunDirectory:dir,SettingsFile:settings};
  assert.equal(JSON.parse(await worker.request('policy',{...args,Mode:'capture'})).mode,'capture');
  const pid=worker.metrics[0].workerPid;
  await worker.request('policy',{...args,Mode:'hide'});await worker.request('policy',{...args,Mode:'hide'});
  const fixture=path.join(root,'test-results/wind-row17-20261117/一级市场招标20261116.xlsx');
  if(await fs.stat(fixture).catch(()=>null)){
   for(const name of ['one','two'])await worker.request('xlsx',{Mode:'extract',File:fixture,OutputFile:path.join(dir,name+'.json')});
   assert.deepEqual(JSON.parse(await fs.readFile(path.join(dir,'one.json'),'utf8')),JSON.parse(await fs.readFile(path.join(dir,'two.json'),'utf8')));
  }
  await assert.rejects(worker.request('xlsx',{Mode:'extract',File:path.join(dir,'missing.xlsx'),OutputFile:path.join(dir,'bad.json')}));
  assert.equal(JSON.parse(await worker.request('policy',{...args,Mode:'status'})).clean,true);
  assert.ok(worker.metrics.every(m=>m.workerPid===pid));
  await assert.rejects(worker.request('unsupported',{}),/Unsupported/);
 }finally{await worker.close();assert.equal(worker.child,null);await fs.rm(dir,{recursive:true,force:true});}
});
