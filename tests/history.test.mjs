import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import {normalizeHistory,mergeHistoryRecords,readReportHistory}from '../src/history.mjs';
import {summarize}from '../src/core.mjs';
const row=(date,index=50)=>({date,bins:[1,0,0,0,0,0],index,oldIndex:51,n:1,text:''});
test('种子补齐日期，升级保留本地同日记录，重复日期去重排序且不改输入',()=>{
 const seed=[row('2026-11-12'),row('2026-11-11'),row('2026-11-12',51)],local=[{...row('2026-11-12',60),text:'本地重跑记录'}],snapshot=JSON.stringify([seed,local]);
 const merged=mergeHistoryRecords(seed,local);assert.equal(merged.length,2);assert.equal(merged[0].date,'2026-11-11');assert.equal(merged[1].index,60);assert.equal(merged[1].text,'本地重跑记录');assert.equal(JSON.stringify([seed,local]),snapshot);
 assert.equal(mergeHistoryRecords(merged,[row('2026-11-12',62)]).length,2);
});
test('缺失历史值保留null，种子仅导出授权汇总字段',()=>{
 const value={date:'2026-11-11',bins:[null,null,null,null,null,null],index:null,oldIndex:58.5,n:null,text:'',token:'not-exported',issuer:'not-exported'};
 const result=normalizeHistory([value])[0];assert.equal(result.n,null);assert.equal(result.index,null);assert.deepEqual(result.bins,value.bins);assert.deepEqual(Object.keys(result),['date','bins','index','oldIndex','n','text']);
 assert.throws(()=>normalizeHistory([row('2026-02-30')]),/日期/);assert.throws(()=>normalizeHistory([{...row('2026-11-11'),n:2}]),/不一致/);
});
test('首次报告读种子，回溯排除当日及未来记录，读取不写成功历史',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'sentiment-history-'));try{
  const seed=path.join(root,'seed.json'),local=path.join(root,'history.json');await fs.writeFile(seed,JSON.stringify([row('2026-11-11'),row('2026-11-12'),row('2026-11-13')]));
  const result=await readReportHistory(seed,local,'2026-11-12');assert.deepEqual(result.map(x=>x.date),['2026-11-11']);await assert.rejects(fs.access(local),{code:'ENOENT'});
  await fs.writeFile(local,JSON.stringify([row('2026-11-11',60)]));assert.equal((await readReportHistory(seed,local,'2026-11-12'))[0].index,60);
  await fs.writeFile(local,'broken');await assert.rejects(readReportHistory(seed,local,'2026-11-12'),/原文件已保留/);assert.equal(await fs.readFile(local,'utf8'),'broken');
 }finally{for(const file of ['seed.json','history.json'])await fs.unlink(path.join(root,file)).catch(e=>{if(e.code!=='ENOENT')throw e;});await fs.rmdir(root);}
});
test('当日新旧指数仅取当日有效逐券样本',()=>{
 const daily=summarize([{spread:-3},{spread:3},{spread:10}]);
 mergeHistoryRecords([row('2026-11-11',99)]);const repeated=summarize([{spread:-3},{spread:3},{spread:10}]);
 assert.deepEqual(repeated,daily);assert.equal(daily.index,37.5);assert.equal(daily.oldIndex,48.5);
});
