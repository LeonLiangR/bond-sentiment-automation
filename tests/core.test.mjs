import test from 'node:test';import assert from 'node:assert/strict';
import {filterSamples,scoreSpread,summarize,makeScenario,bindUploaded,joinResults,ASSET} from '../src/core.mjs';
test('筛选同时剔除空白和零，并保留重复简称的独立样本ID',()=>{const r=filterSamples([{row:9,name:'同名',type:'公司债券',coupon:.02},{row:10,name:'同名',type:'公司债券',coupon:.02},{row:11,name:'零',type:'公司债券',coupon:0},{row:12,name:'空',type:'公司债券',coupon:' '},{row:13,name:'排除',type:'超短期融资券(SCP)',coupon:.02}],'2026-11-12');assert.equal(r.samples.length,2);assert.notEqual(r.samples[0].sampleId,r.samples[1].sampleId);assert.equal(r.excluded.length,3);});
test('斜坡计分边界和正负不对称',()=>{for(const[x,v]of [[-20,1],[-10,1],[-5,2/7],[-3,0],[0,0],[3,0],[5,-3/7],[10,-1.5],[20,-1.5]])assert.ok(Math.abs(scoreSpread(x)-v)<1e-12);assert.equal(scoreSpread(3.00000000003),0);assert.throws(()=>summarize([]),/没有有效/);assert.equal(summarize([{spread:3}]).bins[3],1);});
const wind={code:'123456.SH',issuer:'某发行人有限公司',windType:'一般公司债',term:5,option:'3+2',subordinate:'否',green:'否',science:'是',guarantor:0};
const scenarios=[1,2].map(i=>makeScenario({sampleId:'id'+i,name:'同简称',coupon:.02},wind));
const rows=[1,2].map(i=>({id:'row'+i,batchId:'batch',orderNum:String(i),ptName:wind.issuer,term:'3',termUnit:'Y',assetDtlCategCode:ASSET.公司债,thematicBonds:'03',issueMode:'1',renewalFlg:'0',secoFlg:'0',guarType:'0',isSuccess:'1'}));
test('DQ结果重排及重复发行条件仍一一对应；缺失、重复、篡改均拒绝',()=>{const bindings=bindUploaded(scenarios,[...rows].reverse());assert.deepEqual(bindings.map(b=>b.dqId),['row1','row2']);assert.throws(()=>bindUploaded(scenarios,[rows[0],rows[0]]));assert.throws(()=>bindUploaded(scenarios,[rows[0]]));assert.throws(()=>bindUploaded(scenarios,[rows[0],{...rows[1],term:'5'}]));const results=rows.map((r,i)=>({...r,isCalculate:'1',valDate:'2026-11-12',prcMin:1.7+i*.1,prcMax:1.9+i*.1})).reverse();const j=joinResults(scenarios,bindings,results,'2026-11-12');assert.equal(j.valid[0].dq.id,'row1');assert.equal(j.valid[1].dq.id,'row2');assert.throws(()=>joinResults(scenarios,bindings,results.map(r=>({...r,valDate:'2026-11-11'})),'2026-11-12'));});
test('期限和主题转换保持底稿口径；未知含权表达式不得默认',()=>{assert.equal(scenarios[0].term,3);assert.equal(scenarios[0].guarantor,'');assert.equal(scenarios[0].theme,'科创主题债券');assert.throws(()=>makeScenario({sampleId:'bad'}, {...wind,option:'未知'}));});
test('恢复运行时重新核对方案指纹，拒绝关联表篡改和过期定价',()=>{
 const bindings=bindUploaded(scenarios,rows),results=rows.map(r=>({...r,isCalculate:'1',valDate:'2026-11-12',prcMin:1.7,prcMax:1.9}));
 assert.throws(()=>joinResults(scenarios,[{...bindings[0],sampleId:'id2'},bindings[1]],results,'2026-11-12'),/ID缺失或重复/);
 assert.throws(()=>joinResults(scenarios,[{...bindings[0],scenarioHash:'stale'},bindings[1]],results,'2026-11-12'),/当前提交方案不一致/);
 assert.throws(()=>joinResults(scenarios,bindings,[{...results[0],thematicBonds:'01'},results[1]],'2026-11-12'),/条件发生默认替换或错配/);
});
