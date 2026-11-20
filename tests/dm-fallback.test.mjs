import test from 'node:test';import assert from 'node:assert/strict';
import {makeDmScenario,resolvePricingScenarios}from '../src/dm-fallback.mjs';
import {makeScenario,uploadRow,bindUploaded,joinResults,summarize,ASSET,THEMES}from '../src/core.mjs';
import {buildReportPlan}from '../src/report-plan.mjs';
const sample={sampleId:'d:17',sourceRow:17,name:'26测试MTN001',dmType:'中期票据(MTN)',coupon:.02};
const record=()=>({ok:true,sampleId:sample.sampleId,match:{bondUniCode:123,bondCode:'123.IB',bondShortName:sample.name,comFullName:'测试有限公司'},basic:{bondUniCode:123,code:'123.IB',shortName:sample.name,issuer:'测试有限公司',tenor:'3.00Y',bondTypePar:8},f9:{bondUniCode:123,bondCode:'123.IB',bondShortName:sample.name,guaranteedStatus:0,publicOffering:1,perpetualStatus:0,subordinatedBondStatus:false,greenBondStatus:null,scienceTechNoteStatus:null,stiStatus:null},batch:{bondUniCode:123,bondCode:'123.IB',bondShortName:sample.name,comFullName:'测试有限公司',bondType:8,guaranteedStatus:0}});
const raw={headers:[null,null,null,null,null,null,null,'发行期限(年)'],rows:[{row:17,name:sample.name,values:[null,null,null,null,null,null,null,'3']}]};
const wind={sampleId:sample.sampleId,name:sample.name,code:'q-optional',issuer:'Wind有限公司',guarantor:0,windType:'一般中期票据',term:5,option:0,green:'是',science:'否',subordinate:'否'};
test('DM整条生成DQ输入，主题成功返回空值时为否，不能混入Wind字段',async()=>{
 const failed={...wind,windFailure:'issuer:0'};let requests;
 const result=await resolvePricingScenarios([sample],[failed],raw,async samples=>{requests=samples;return[record()];});
 assert.equal(requests.length,1);assert.equal(result.scenarios.length,1);assert.equal(result.excluded.length,0);
 const s=result.scenarios[0];assert.equal(s.dataSource,'DM');assert.equal(s.wind,undefined);assert.equal(s.dm.themeDefaulted,true);
 assert.deepEqual(uploadRow(s,1),[1,'测试有限公司',null,3,'Y','短融/中票','否','公募','不可续期','非次级']);
 const uploaded={id:'r',batchId:'b',orderNum:1,ptName:s.issuer,term:3,termUnit:'Y',assetDtlCategCode:ASSET[s.bondType],thematicBonds:THEMES[s.theme],issueMode:'1',renewalFlg:'0',secoFlg:'0',isSuccess:'1'};
 assert.equal(bindUploaded([s],[uploaded])[0].scenarioHash,s.scenarioHash);
});
test('Wind信息完整时不查DM；不以Wind代码作为准入条件',async()=>{
 const r=await resolvePricingScenarios([sample],[wind],raw,async()=>{throw Error('Should not query DM');});
 assert.deepEqual(r.scenarios,[makeScenario(sample,wind)]);assert.deepEqual(r.audit,[]);
});
test('DM主题非空照实映射；担保人全称、含权、私募及次级只来自DM',()=>{
 const r=record();r.f9.greenBondStatus=1;r.f9.scienceTechNoteStatus=1;assert.equal(makeDmScenario(sample,r,raw).theme,'绿色债券');
 r.f9.greenBondStatus=null;assert.equal(makeDmScenario(sample,r,raw).theme,'科创主题债券');
 r.f9.guaranteedStatus=1;r.batch.guaranteedStatus=1;r.basic.guruName='担保有限公司';r.f9.perpetualStatus=1;r.f9.publicOffering=0;r.f9.subordinatedBondStatus=true;
 const source=structuredClone(raw);source.rows[0].values[7]='3+N';r.basic.tenor='3+N';
 const s=makeDmScenario(sample,r,source);assert.equal(s.guarantor,'担保有限公司');assert.equal(s.term,3);assert.equal(s.issueMode,'私募');assert.equal(s.renewal,'可续期');assert.equal(s.subordinate,'次级');
});
test('DM查询失败、错券、缺字段、冲突不会被当作无担保或非主题债',()=>{
 for(const mutate of [r=>{r.ok=false;r.error='network';},r=>r.basic.bondUniCode++,r=>r.basic.shortName+='A',r=>r.f9.perpetualStatus=null,r=>r.f9.subordinatedBondStatus=null,r=>r.f9.publicOffering=null,r=>{r.f9.guaranteedStatus=1;r.batch.guaranteedStatus=1;},r=>r.basic.guruName='意外担保人',r=>r.f9.greenBondStatus=99,r=>r.batch.publicOffering=0,r=>r.basic.tenor='5.00Y']){
  const r=record();mutate(r);assert.throws(()=>makeDmScenario(sample,r,raw));
 }
});
test('补全失败仅排除该券，保留其他券和样本顺序；重复关联必须报错',async()=>{
 const good={...sample,sampleId:'good',sourceRow:18,name:'另一只'},failed={...wind,issuer:0,windType:0};
 const result=await resolvePricingScenarios([sample,good],[failed,{...wind,sampleId:good.sampleId}],raw,async()=>[{ok:false,sampleId:sample.sampleId,error:'未唯一匹配'}]);
 assert.equal(result.scenarios[0].sampleId,'good');assert.equal(result.excluded[0].sampleId,sample.sampleId);assert.match(result.excluded[0].reason,/未唯一匹配/);
 await assert.rejects(resolvePricingScenarios([sample,good],[failed,failed],raw),/ID/);
 await assert.rejects(resolvePricingScenarios([sample],[failed],raw,async()=>[]),/ID/);
});
test('DM补全样本沿用DQ绑定与计分，报告标明来源和债券代码',()=>{
 const s=makeDmScenario(sample,record(),raw);
 const row={id:'r',batchId:'b',orderNum:1,ptName:s.issuer,term:s.term,termUnit:'Y',assetDtlCategCode:ASSET[s.bondType],thematicBonds:THEMES[s.theme],issueMode:'1',renewalFlg:'0',secoFlg:'0',isSuccess:'1',isCalculate:'1',valDate:'2026-11-16',prcMin:1.9,prcMax:2.1};
 const bindings=bindUploaded([s],[row]),{valid,excluded}=joinResults([s],bindings,[row],'2026-11-16');
 assert.equal(valid[0].spread,0);assert.equal(valid[0].score,0);
 const source={...raw,rows:raw.rows.map(r=>({...r,type:sample.dmType,coupon:sample.coupon})),title:'11月16日'};
 const plan=buildReportPlan({date:'2026-11-16',valid,excluded,sampleA:[sample],summary:summarize(valid),raw:source,history:[],reportText:'测试'});
 assert.equal(plan.samples[0][3],'123.IB');assert.equal(plan.samples[0][14],'定价有效（DM补全）');assert.equal(plan.headers.samples[3],'债券代码');assert.equal(plan.dq[0][15],'定价有效');
});
function retryFixture(){
 const s={...sample,name:sample.name+'A'},r=record(),source=structuredClone(raw);
 for(const [o,key]of [[r.match,'bondShortName'],[r.basic,'shortName'],[r.f9,'bondShortName'],[r.batch,'bondShortName']])o[key]=s.name;
 source.rows[0].name=s.name;source.rows[0].values[10]='测试有限公司';
 const w={...wind,name:s.name,issuer:'测试有限公司',term:3,green:'否',windRetry:{originalName:s.name,queryName:sample.name}};
 return{s,r,source,w};
}
test('Wind去末尾A/B重试成功后仍保留原名、ID及排序，不调用DM',async()=>{
 const {s,source,w}=retryFixture();let calls=0;
 const result=await resolvePricingScenarios([s],[w],source,async()=>{calls++;throw Error('Not needed');});
 assert.equal(calls,0);assert.equal(result.scenarios[0].name,s.name);assert.equal(result.scenarios[0].sampleId,s.sampleId);assert.equal(result.scenarios[0].wind.windRetry.queryName,sample.name);
});
test('Wind去后缀仍失败、取到不同品种或改动其他字符时，用原DM简称补全',async()=>{
 for(const mutate of [w=>w.windFailure='issuer:0',w=>w.term=5,w=>w.issuer='其他有限公司',w=>w.windRetry.queryName+='C']){
  const {s,r,source,w}=retryFixture();mutate(w);let requested;
  const result=await resolvePricingScenarios([s],[w],source,async samples=>{requested=samples;return[r];});
  assert.equal(requested[0].name,s.name);assert.equal(result.scenarios[0].dataSource,'DM');assert.equal(result.scenarios[0].wind,undefined);assert.equal(result.scenarios[0].name,s.name);
 }
});
