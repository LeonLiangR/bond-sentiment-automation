import {createHash} from 'node:crypto';
export const TYPES=new Set(['公司债券','中期票据(MTN)','定向工具(PPN)','证券公司债']);
export const ASSET={公司债:'122005002000000,122005002001000,122005002002000,122005002003000',企业债:'122005001000000,122005001001000,122005001002000,122005001003000,122005001004000','短融/中票':'122005003001000,122005003002000,122005003003000',不限:'ALL'};
export const THEMES={否:'01',绿色债券:'02',科创主题债券:'03',三农主题债券:'04',小微主题债券:'05'};
export function filterSamples(raw,date){
 const samples=[],excluded=[];
 for(const r of raw){
  const item={sampleId:date+':'+r.row,sourceRow:r.row,name:String(r.name??'').trim(),dmType:String(r.type??'').trim(),coupon:r.coupon};
  let reason;
  if(!TYPES.has(item.dmType))reason='非指定债券类型';
  else if(r.coupon===null||r.coupon===undefined||String(r.coupon).trim()==='')reason='中标利率为空';
  else if(!Number.isFinite(Number(r.coupon)))reason='中标利率不是数值';
  else if(Number(r.coupon)===0)reason='中标利率为0';
  else if(!item.name)reason='债券简称为空';
  else if(Number(r.coupon)<0||Number(r.coupon)>1)reason='中标利率单位或数值异常';
  if(reason)excluded.push({...item,stage:'DM筛选',reason});else samples.push({...item,coupon:Number(r.coupon)});
 }
 if(new Set(samples.map(x=>x.sampleId)).size!==samples.length)throw Error('DM原始行ID重复');
 return {samples,excluded};
}
export function makeScenario(sample,wind){
 const required=['code','issuer','guarantor','windType','term','option','subordinate','green','science'];
 for(const key of required)if(wind[key]===null||wind[key]===undefined||String(wind[key]).trim()===''||String(wind[key]).startsWith('#'))throw Error('Wind字段缺失或错误：'+key);
 if(!/^\d{6,9}\.(IB|SH|SZ)$/.test(wind.code))throw Error('Wind未返回唯一有效代码');
 if(!['是','否'].includes(wind.subordinate)||!['是','否'].includes(wind.green)||!['是','否'].includes(wind.science))throw Error('Wind标识字段异常');
 const option=String(wind.option),rawTerm=Number(wind.term);
 const term=(option==='0')?rawTerm:Number(option.split('+')[0]);
 if(!(term>0&&term<=5000)||option!=='0'&&!/^\d+(?:\.\d+)?\+(?:\d+(?:\.\d+)?|N)(?:\+(?:\d+(?:\.\d+)?|N))*$/.test(option))throw Error('含权期限格式不支持或期限非正数');
 const type=['一般公司债','私募债'].includes(wind.windType)?'公司债':wind.windType==='一般企业债'?'企业债':['一般中期票据','定向工具'].includes(wind.windType)?'短融/中票':'不限';
 const theme=wind.green==='是'?'绿色债券':wind.science==='是'?'科创主题债券':'否';
 const guarantor=wind.guarantor===0||wind.guarantor==='0'||wind.guarantor===null?'':String(wind.guarantor??'').trim();
 if(guarantor.startsWith('#'))throw Error('担保人字段错误');
 const s={...sample,wind,issuer:String(wind.issuer).trim(),guarantor,term,termUnit:'Y',bondType:type,theme,issueMode:/定向|私募/.test(wind.windType)?'私募':'公募',renewal:option.includes('+N')?'可续期':'不可续期',subordinate:wind.subordinate==='否'?'非次级':'次级'};
 s.scenarioHash=createHash('sha256').update(JSON.stringify([s.issuer,s.guarantor,s.term,s.bondType,s.theme,s.issueMode,s.renewal,s.subordinate])).digest('hex');
 return s;
}
export function uploadRow(s,seq){return [seq,s.issuer,s.guarantor||null,s.term,s.termUnit,s.bondType,s.theme,s.issueMode,s.renewal,s.subordinate];}
const cleanName=v=>String(v??'').replace(/[()（）\s]/g,'');
export function bindUploaded(scenarios,rows){
 if(rows.length!==scenarios.length)throw Error(`DQ上传记录数不一致：${rows.length}/${scenarios.length}`);
 const seqs=new Set(),ids=new Set(),batchIds=new Set();
 const bindings=[];
 for(const r of rows){
  const seq=Number(r.orderNum),s=scenarios[seq-1];
  if(!Number.isInteger(seq)||!s||seqs.has(seq)||!r.id||ids.has(r.id)||!r.batchId)throw Error('DQ提交序号或记录ID缺失、重复');
  seqs.add(seq);ids.add(r.id);batchIds.add(r.batchId);
  if(cleanName(r.ptName)!==cleanName(s.issuer))throw Error('DQ发行人错配：'+s.name);
  const normalized={seq,sampleId:s.sampleId,dqId:r.id,batchId:r.batchId,scenarioHash:s.scenarioHash,matched:r.isSuccess!=='0'};
  if(normalized.matched){
   const expected={term:s.term,termUnit:s.termUnit,assetDtlCategCode:ASSET[s.bondType],thematicBonds:THEMES[s.theme],issueMode:s.issueMode==='公募'?'1':'2',renewalFlg:s.renewal==='可续期'?'1':'0',secoFlg:s.subordinate==='次级'?'1':'0'};
   for(const [key,value]of Object.entries(expected))if(String(r[key])!==String(value))throw Error('DQ条件发生默认替换或错配：'+s.name+' / '+key);
   if(s.guarantor&&cleanName(r.gutorNm)!==cleanName(s.guarantor))throw Error('DQ担保人不一致：'+s.name);
   if(!s.guarantor&&r.gutorNm&&!['E','0'].includes(r.gutorNm))throw Error('DQ意外增加担保人：'+s.name);
  }
  bindings.push(normalized);
 }
 if(batchIds.size!==1)throw Error('DQ返回多个批次，可能有其他操作同时修改工作列表');
 return bindings.sort((a,b)=>a.seq-b.seq);
}
export function calculationRows(rows){return rows.filter(r=>r.isSuccess!=='0').map((r,i)=>{
 const s={...r,type:'GENERAL',showNum:i,termType:'3',curValType:1};
 if(r.gutorId==='E'||r.gutorNm==='E')Object.assign(s,{needTransGuarType:true,guarType:'0',gutorId:null,gutorNm:null,gutorOptions:[],gutorDisabled:true});
 return omitEmpty(s);
});}
function omitEmpty(v){return Array.isArray(v)?v.map(omitEmpty):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).filter(([,x])=>x!==null&&x!=='').map(([k,x])=>[k,omitEmpty(x)])):v;}
export function joinResults(scenarios,bindings,results,date){
 if(results.length!==bindings.length)throw Error('DQ计算前后记录数发生变化');
 const checked=bindUploaded(scenarios,results),bySeq=new Map(checked.map(b=>[b.seq,b]));
 if(new Set(bindings.map(b=>b.sampleId)).size!==scenarios.length)throw Error('DQ关联样本ID缺失或重复');
 for(const b of bindings){const current=bySeq.get(b.seq);for(const key of ['sampleId','dqId','batchId','scenarioHash'])if(!current||current[key]!==b[key])throw Error('DQ关联记录与当前提交方案不一致：'+key);}
 const resultMap=new Map();for(const r of results){const k=r.batchId+':'+r.id;if(resultMap.has(k))throw Error('DQ结果记录ID重复');resultMap.set(k,r);}
 const scenarioMap=new Map(scenarios.map(s=>[s.sampleId,s])),valid=[],excluded=[];
 for(const b of bindings){
  const s=scenarioMap.get(b.sampleId),r=resultMap.get(b.batchId+':'+b.dqId);
  if(!r||Number(r.orderNum)!==b.seq||cleanName(r.ptName)!==cleanName(s.issuer))throw Error('DQ返回结果标识或发行人发生变化');
  const item={...s,dq:r,binding:b};
  if(!b.matched||r.isSuccess==='0'){excluded.push({...item,stage:'DQ',reason:'发行人匹配失败'});continue;}
  if(r.isCalculate==='0'||!Number.isFinite(r.prcMin)||!Number.isFinite(r.prcMax)||r.prcMin<=0||r.prcMin>r.prcMax){excluded.push({...item,stage:'DQ',reason:'暂不支持定价或无有效区间'});continue;}
  if(r.valDate!==date)throw Error(`DQ估值日期${r.valDate}与业务日期${date}不一致，停止发布`);
  const center=(r.prcMin+r.prcMax)/2,spread=roundBP((s.coupon*100-center)*100);
  valid.push({...item,center,spread,score:scoreSpread(spread)});
 }
 if(valid.length+excluded.length!==scenarios.length)throw Error('最终样本数量不守恒');
 return {valid,excluded};
}
export const roundBP=v=>Math.sign(v)*Math.round(Math.abs(v)*10000+1e-7)/10000;
export function scoreSpread(s){s=roundBP(s);return Math.abs(s)<=3?0:s<0?Math.min((-3-s)/7,1):-1.5*Math.min((s-3)/7,1);}
export function summarize(valid){
 const spreads=valid.map(x=>x.spread),scores=spreads.map(scoreSpread),n=scores.length;
 if(!n)throw Error('没有有效定价样本，不能输出情绪指数');
 const bins=[spreads.filter(x=>x<-5).length,spreads.filter(x=>x>=-5&&x<-3).length,spreads.filter(x=>x>=-3&&x<3).length,spreads.filter(x=>x>=3&&x<5).length,spreads.filter(x=>x>=5&&x<10).length,spreads.filter(x=>x>=10).length];
 const sum=scores.reduce((a,b)=>a+b,0),mean=sum/n,variance=n<2?null:scores.reduce((a,x)=>a+(x-mean)**2,0)/(n-1);
 return {n,bins,scoreSum:sum,mean,index:50+25*mean,oldIndex:50+bins[0]+bins[1]*.5-bins[3]*.5-bins[4]-bins[5]*1.5,confidence:n>=25?'正常':n>=15?'样本偏少':'低置信',se:variance===null?null:25*Math.sqrt(variance/n),netLow:(bins[0]+bins[1]-bins[3]-bins[4]-bins[5])/n,negative:spreads.filter(x=>x<0).length,zero:spreads.filter(x=>x===0).length,positive:spreads.filter(x=>x>0).length,negative10:spreads.filter(x=>x<=-10).length,positiveMin:spreads.some(x=>x>0)?Math.min(...spreads.filter(x=>x>0)):null,positiveMax:spreads.some(x=>x>0)?Math.max(...spreads.filter(x=>x>0)):null};
}
export function makeNarrative(date,s,history){
 const [y,m,d]=date.split('-').map(Number),previous=history.filter(h=>h.date<date&&typeof h.index==='number').at(-1),parts=[`${m}月${d}日可统计公司债券、中期票据、定向工具及证券公司债样本共计${s.n}只债券，市场价格情绪指数为${s.index.toFixed(2)}。`];
 if(previous){const delta=s.index-previous.index,change=Math.abs(delta).toFixed(2);parts.push(change==='0.00'?'较上一有效统计日基本持平。':`较上一有效统计日${delta>0?'上升':'下降'}${change}点，发行定价情绪${delta>0?'有所改善':'有所转弱'}。`);}
 parts.push(`从具体估值偏离幅度看，低估值发行${s.negative}只，其中低估值10BP及以上${s.negative10}只；平估值发行${s.zero}只；高估值发行${s.positive}只${s.positive?`，偏离${s.positiveMin}—${s.positiveMax}BP`:''}。高估值3—5BP共${s.bins[3]}只，5—10BP共${s.bins[4]}只，10BP及以上共${s.bins[5]}只。`);
 if(s.n<25)parts.push(`当日${s.confidence}，指数仅供参考。`);
 return parts.join('');
}
