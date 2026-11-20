import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import os from'node:os';import path from'node:path';
import {exportHistory,importHistory,historySummary,parseHistoryTransfer}from'../src/history-transfer.mjs';
const row=(date,index=50)=>({date,bins:[1,0,0,0,0,0],index,oldIndex:51,n:1,text:''});
async function setup(){const dir=await fs.mkdtemp(path.join(os.tmpdir(),'sentiment-handoff-')),dataDir=path.join(dir,'state'),rootDir=path.join(dir,'app');await fs.mkdir(dataDir);await fs.mkdir(rootDir);return{dir,dataDir,rootDir,seedFile:path.join(rootDir,'seed.json'),localFile:path.join(dataDir,'history.json')};}
test('交接导出包含种子及本机完整历史，去重排序且只导出汇总字段',async()=>{
 const p=await setup();try{
  await fs.writeFile(p.seedFile,JSON.stringify([row('2026-10-30'),row('2026-10-29')]));
  await fs.writeFile(p.localFile,JSON.stringify([{...row('2026-10-30',60),secret:'never exported',rawBonds:[1],settings:{password:'never exported'}},row('2026-11-02')]));
  const outputFile=path.join(p.dir,'handoff.json'),result=await exportHistory({...p,outputFile}),data=JSON.parse(await fs.readFile(outputFile,'utf8'));
  assert.equal(result.count,3);assert.equal(result.firstDate,'2026-10-29');assert.equal(result.lastDate,'2026-11-02');assert.equal(data.records[1].index,60);
  assert.deepEqual(Object.keys(data.records[0]),['date','bins','index','oldIndex','n','text']);assert.ok(!JSON.stringify(data).includes('secret'));assert.ok(!JSON.stringify(data).includes('password'));
  assert.deepEqual(parseHistoryTransfer(data).records,data.records);
  await assert.rejects(exportHistory({...p,outputFile:p.localFile}),/不要覆盖/);
 }finally{await fs.rm(p.dir,{recursive:true,force:true});}
});
test('月度接班补齐日期，保留本机冲突并备份；重复导入不重复或改写',async()=>{
 const p=await setup();try{
  await fs.writeFile(p.seedFile,JSON.stringify([row('2026-10-29')]));const original=JSON.stringify([row('2026-10-30',60)]);await fs.writeFile(p.localFile,original);
  const inputFile=path.join(p.dir,'incoming.json');await fs.writeFile(inputFile,JSON.stringify([row('2026-10-29'),row('2026-10-30',70),row('2026-11-02'),row('2026-11-02')]));
  const result=await importHistory({...p,inputFile});assert.equal(result.added,1);assert.equal(result.identical,1);assert.equal(result.duplicates,1);assert.equal(result.conflictCount,1);assert.deepEqual(result.conflictDates,['2026-10-30']);assert.equal(await fs.readFile(result.backupFile,'utf8'),original);
  const saved=await fs.readFile(p.localFile,'utf8'),records=JSON.parse(saved);assert.equal(records[1].index,60);assert.equal(records.length,3);
  const repeat=await importHistory({...p,inputFile});assert.equal(repeat.added,0);assert.equal(repeat.backupFile,null);assert.equal(await fs.readFile(p.localFile,'utf8'),saved);
  assert.deepEqual(await historySummary(p.seedFile,p.localFile),{count:3,firstDate:'2026-10-29',lastDate:'2026-11-02'});
  await assert.rejects(fs.access(path.join(p.dataDir,'run.lock')),{code:'ENOENT'});
 }finally{await fs.rm(p.dir,{recursive:true,force:true});}
});
test('错误格式、日期、分档、版本及文件内冲突全部拒绝，原历史不变',async()=>{
 const p=await setup();try{
  const before=JSON.stringify([row('2026-10-30')]);await fs.writeFile(p.localFile,before);const inputFile=path.join(p.dir,'incoming.json');
  for(const value of [{format:'bond-sentiment-history',version:2,records:[row('2026-11-02')]},[row('2026-02-30')],[{...row('2026-11-02'),n:5}],[{...row('2026-11-02'),index:'50'}],[row('2026-11-02'),row('2026-11-02',51)],[],{settings:{password:'data only'}}]){
   await fs.writeFile(inputFile,JSON.stringify(value));await assert.rejects(importHistory({...p,inputFile}));assert.equal(await fs.readFile(p.localFile,'utf8'),before);
  }
  await fs.writeFile(inputFile,'broken');await assert.rejects(importHistory({...p,inputFile}),/无法解析/);assert.equal(await fs.readFile(p.localFile,'utf8'),before);
 }finally{await fs.rm(p.dir,{recursive:true,force:true});}
});
test('活动日报锁阻止导入；过期锁可恢复；旧数组和BOM文件兼容',async()=>{
 const p=await setup();try{
  const inputFile=path.join(p.dir,'incoming.json');await fs.writeFile(inputFile,'\uFEFF'+JSON.stringify([row('2026-11-02')]));const lock=path.join(p.dataDir,'run.lock');
  await fs.writeFile(lock,JSON.stringify({pid:process.pid}));await assert.rejects(importHistory({...p,inputFile}),/已有报告/);await assert.rejects(fs.access(p.localFile),{code:'ENOENT'});
  // An impossibly large PID is confirmed absent by the OS, as in a crashed run.
  await fs.writeFile(lock,JSON.stringify({pid:2147483647}));const result=await importHistory({...p,inputFile});assert.equal(result.added,1);assert.equal(result.count,1);
 }finally{await fs.rm(p.dir,{recursive:true,force:true});}
});
