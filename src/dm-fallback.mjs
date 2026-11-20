import {evaluateDmPage}from './dm.mjs';
import {pricingScenarioHash,makeScenario}from './core.mjs';

const normal=value=>String(value??'').replace(/[\s()（）]/g,'').toUpperCase();
const flag=value=>value===true||value===1||value==='1'?1:value===false||value===0||value==='0'?0:null;
function requiredFlag(value,label){const n=flag(value);if(n===null)throw Error('DM'+label+'未返回有效标志');return n;}
const text=value=>typeof value==='string'?value.trim():'';

// Kept inside the logged-in page. Fixed read-only methods; no credentials leave DM.
async function pageReadTerms(samples,loadModules){
 const find=loadModules();
 const selectQuery=(exports,route)=>{
  const matches=Object.values(exports).filter(value=>typeof value==='function'&&route(String(value)));
  if(matches.length===1)return matches[0];
 };
 const search=find('个券搜索','/onshore-search-service','/api/search/gathering',selectQuery);
 const f9Query=find('个券详情','/onshore-bond-basic','/api/bond/onshore/f9',selectQuery);
 const batchQuery=find('批量条款','/onshore-bond-basic','/api/bond/filter/simple/v3/onshore/batch',selectQuery);
 const basicClient=find('基本条款','/bond-web','/api/bond/bonds/maincls/',(exports,route)=>{
  const matches=Object.values(exports).filter(value=>typeof value?.getBond==='function'&&typeof value?.getBondSpecialItems==='function'&&route(String(value.getBondSpecialItems)));
  if(matches.length===1)return matches[0];
 });
 const pick=(o,keys)=>Object.fromEntries(keys.filter(k=>Object.hasOwn(o||{},k)).map(k=>[k,o[k]]));
 const normalize=s=>String(s??'').replace(/[\s()（）]/g,'').toUpperCase();
 const result=new Array(samples.length);let next=0;
 async function worker(){while(next<samples.length){const i=next++,sample=samples[i];try{
  const found=await search({data:{keyword:sample.name,pageSize:30},config:{timeout:25000}});
  if(!Array.isArray(found?.onshoreBondInfoSearchResults))throw Error('DM搜索返回格式变化');
  const exact=[...new Map(found.onshoreBondInfoSearchResults.filter(b=>normalize(b.bondShortName)===normalize(sample.name)).map(b=>[b.bondUniCode,b])).values()];
  if(exact.length!==1)throw Error('DM简称精确匹配为'+exact.length+'条，不能自动选券');
  const match=pick(exact[0],['bondUniCode','bondCode','bondShortName','bondFullName','comFullName']);
  const id=match.bondUniCode;if(!Number.isSafeInteger(id)||id<=0)throw Error('DM债券标识无效');
  const [basic,f9,batch]=await Promise.all([
   basicClient.getBond(id),
   f9Query({params:{bondUniCode:id},config:{timeout:25000}}),
   batchQuery({data:{bondUniCodes:[id]},config:{timeout:25000}})
  ]);
  if(!Array.isArray(batch)||batch.length!==1||batch[0].bondUniCode!==id)throw Error('DM批量资料返回标识不一致');
  result[i]={ok:true,sampleId:sample.sampleId,match,
   basic:pick(basic,['bondUniCode','code','shortName','fullName','issuer','guruName','bondTypePar','dmBondTypeName','tenor','bondCalMatu','inteStartDate']),
   f9:pick(f9,['bondUniCode','bondCode','bondShortName','bondFullName','guaranteedStatus','publicOffering','perpetualStatus','subordinatedBondStatus','greenBondStatus','scienceTechNoteStatus','stiStatus','tenor','issueDate','paymentOrder']),
   batch:pick(batch[0],['bondUniCode','bondCode','bondShortName','comFullName','bondType','guaranteedStatus','publicOffering','perpetualStatus','subordinatedBondStatus'])};
 }catch(e){result[i]={ok:false,sampleId:sample.sampleId,error:String(e.message||e).slice(0,500)};}}}
 await Promise.all([worker(),worker(),worker()]);return result;
}
export async function readDmPricingTerms(samples){
 const input=samples.map(s=>({sampleId:s.sampleId,name:s.name}));
 const rows=await evaluateDmPage(pageReadTerms,input,{timeout:Math.max(45000,Math.ceil(samples.length/3)*60000)});
 if(!Array.isArray(rows)||rows.length!==samples.length||new Set(rows.map(r=>r.sampleId)).size!==samples.length||rows.some((r,i)=>r.sampleId!==samples[i].sampleId))throw Error('DM补全样本ID或数量不一致');
 return rows;
}

export function makeDmScenario(sample,record,raw){
 if(!record?.ok)throw Error(record?.error||'DM条款未返回');
 const {match,basic:b,f9:f,batch:v}=record,id=match?.bondUniCode;
 if(record.sampleId!==sample.sampleId||!Number.isSafeInteger(id)||[b?.bondUniCode,f?.bondUniCode,v?.bondUniCode].some(value=>value!==id))throw Error('DM债券标识不一致');
 if([match.bondShortName,b.shortName,f.bondShortName,v.bondShortName].some(name=>normal(name)!==normal(sample.name)))throw Error('DM债券简称不一致');
 const issuer=text(b.issuer);if(!issuer||issuer==='0'||normal(issuer)!==normal(v.comFullName)||normal(issuer)!==normal(match.comFullName))throw Error('DM发行人缺失或不一致');
 const code=text(b.code);if(!code||code!==match.bondCode||code!==f.bondCode||code!==v.bondCode)throw Error('DM债券代码缺失或不一致');
 const type=Number(v.bondType),bondType={5:'公司债',8:'短融/中票',22:'短融/中票',37:'不限'}[type];
 const sourceTypes={5:'公司债券',8:'中期票据(MTN)',22:'定向工具(PPN)',37:'证券公司债'};
 if(!bondType||Number(b.bondTypePar)!==type||sample.dmType!==sourceTypes[type])throw Error('DM债券类型缺失或不一致');
 const guaranteed=requiredFlag(f.guaranteedStatus,'担保属性'),guarantor=text(b.guruName);
 if(guaranteed!==requiredFlag(v.guaranteedStatus,'担保属性')||guaranteed===1&&!guarantor||guaranteed===0&&guarantor)throw Error('DM担保标志与担保人全称缺失或冲突');
 const source=raw?.rows?.find(r=>r.row===sample.sourceRow);
 if(!source||normal(source.name)!==normal(sample.name)||!String(raw.headers?.[7]).includes('年'))throw Error('DM原始期限行或单位未核实');
 const contract=String(source.values[7]??'').trim().replace(/\s/g,'').toUpperCase();
 if(!/^\d+(?:\.\d+)?(?:\+(?:\d+(?:\.\d+)?|N))*$/.test(contract))throw Error('DM合同期限格式不支持：'+contract);
 const term=Number(contract.split('+')[0]);if(!(term>0&&term<=5000))throw Error('DM有效期限非正数或超限');
 const declared=text(b.tenor).replace(/Y$/i,'');
 if(!/^\d+(?:\.\d+)?(?:\+(?:\d+(?:\.\d+)?|N))*$/.test(declared)||Math.abs(Number(declared.split('+')[0])-term)>0.011)throw Error('DM原表期限与个券期限不一致');
 const perpetual=requiredFlag(f.perpetualStatus,'可续期属性');if(contract.includes('N')&&!perpetual)throw Error('DM期限与可续期标志冲突');
 for(const key of ['publicOffering','perpetualStatus','subordinatedBondStatus'])if(flag(v[key])!==null&&flag(v[key])!==requiredFlag(f[key],key))throw Error('DM个券与批量属性冲突：'+key);
 const themes=[f.greenBondStatus,f.scienceTechNoteStatus,f.stiStatus];
 for(const value of themes)if(value!==null&&value!==undefined&&String(value).trim()!==''&&flag(value)===null)throw Error('DM主题债标志无法识别');
 const theme=flag(f.greenBondStatus)===1?'绿色债券':themes.slice(1).some(value=>flag(value)===1)?'科创主题债券':'否';
 const s={...sample,issuer,guarantor,term,termUnit:'Y',bondType,theme,issueMode:requiredFlag(f.publicOffering,'发行方式')?'公募':'私募',renewal:perpetual?'可续期':'不可续期',subordinate:requiredFlag(f.subordinatedBondStatus,'次级属性')?'次级':'非次级',
  dataSource:'DM',referenceCode:code,dm:{id,code,themeDefaulted:themes.every(value=>value===null||value===undefined||String(value).trim()===''),contract}};
 s.scenarioHash=pricingScenarioHash(s);return s;
}

// A failed Wind sample is replaced as a whole. Its cached terms are never mixed into DM terms.
export function checkWindNameRetry(sample,row,raw){
 if(!row.windRetry)return;
 const {originalName,queryName}=row.windRetry;
 if(originalName!==sample.name||!/[AB]$/.test(originalName)||queryName!==originalName.slice(0,-1))throw Error('Wind简称重试身份不一致');
 const source=raw?.rows?.find(r=>r.row===sample.sourceRow),contract=String(source?.values?.[7]??'').trim();
 const term=Number(String(row.option)==='0'?row.term:String(row.option).split('+')[0]);
 if(!source||normal(source.name)!==normal(sample.name)||!String(raw.headers?.[7]).includes('年')||!/^\d+(?:\.\d+)?(?:\+(?:\d+(?:\.\d+)?|N))*$/.test(contract)||Math.abs(Number(contract.split('+')[0])-term)>1e-8)throw Error('Wind去后缀重试期限与DM原券不一致');
 const issuer=text(source.values[10]);if(issuer&&normal(issuer)!==normal(row.issuer))throw Error('Wind去后缀重试发行人与DM原券不一致');
}
export async function resolvePricingScenarios(samples,wind,raw,readDm=readDmPricingTerms){
 if(wind.length!==samples.length||new Set(wind.map(r=>r.sampleId)).size!==samples.length||samples.some(s=>!wind.some(w=>w.sampleId===s.sampleId)))throw Error('Wind样本ID数量不一致');
 const map=new Map(wind.map(r=>[r.sampleId,r])),resolved=new Map(),failed=[];
 for(const sample of samples){const row=map.get(sample.sampleId);try{
  if(row.windFailure)throw Error(row.windFailure);
  checkWindNameRetry(sample,row,raw);
  resolved.set(sample.sampleId,makeScenario(sample,row));
 }catch(e){failed.push({sample,reason:e.message});}}
 let records=[];if(failed.length){try{records=await readDm(failed.map(x=>x.sample));}catch(e){records=failed.map(({sample})=>({sampleId:sample.sampleId,ok:false,error:e.message}));}}
 if(records.length!==failed.length||new Set(records.map(r=>r.sampleId)).size!==records.length||failed.some(x=>!records.some(r=>r.sampleId===x.sample.sampleId)))throw Error('DM补全样本ID或数量不一致');
 const details=new Map(records.map(r=>[r.sampleId,r])),excluded=[],audit=[];
 for(const {sample,reason}of failed){const record=details.get(sample.sampleId);try{const s=makeDmScenario(sample,record,raw);resolved.set(sample.sampleId,s);audit.push({sampleId:sample.sampleId,name:sample.name,windFailure:reason,success:true,record,scenario:s});}
  catch(e){excluded.push({...sample,stage:'条款',reason:'Wind未取得有效条款；DM补全失败：'+e.message});audit.push({sampleId:sample.sampleId,name:sample.name,windFailure:reason,success:false,record,error:e.message});}}
 return {scenarios:samples.filter(s=>resolved.has(s.sampleId)).map(s=>resolved.get(s.sampleId)),excluded,audit};
}
