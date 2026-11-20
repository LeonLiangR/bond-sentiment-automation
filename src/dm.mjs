import fs from 'node:fs/promises';import path from 'node:path';import {createHash}from'node:crypto';import{localJson}from'./local-http.mjs';
export function dmPageModules(page=document){
 const frame=Array.from(page.querySelectorAll('iframe')).map(element=>element.contentWindow).find(candidate=>{try{return candidate.location.origin==='https://web.innodealing.com'&&candidate.location.pathname==='/quote-web/';}catch{return false;}});
 if(!frame?.webpackChunkdmWeb)throw Error('DM数据会话尚未就绪');
 let runtime;frame.webpackChunkdmWeb.push([['sentiment_read_'+Date.now()+'_'+Math.random().toString(36).slice(2)],{},require=>runtime=require]);
 if(!runtime?.m)throw Error('DM数据会话尚未就绪');
 const factories=Object.entries(runtime.m).map(([id,factory])=>[id,String(factory)]);
 return function findExport(label,service,endpoint,select){
  const matchesPath=source=>["'",'"',"`","${"].some(suffix=>source.includes(endpoint+suffix));
  const candidates=factories.filter(([,source])=>source.includes(service)&&matchesPath(source));
  if(candidates.length===1){
   const selected=select(runtime(candidates[0][0]),matchesPath);
   if(selected)return selected;
  }
  throw Error('DM模块版本已变化：无法唯一识别'+label+'，请更新程序适配。');
 };
}
export async function evaluateDmPage(pageFunction,input,{timeout=45000}={}){
 const port=Number((await fs.readFile(path.join(process.env.APPDATA,'DM-Native/cache/DevToolsActivePort'),'utf8')).split(/\r?\n/)[0]);
 if(!Number.isInteger(port)||port<1||port>65535)throw Error('DM会话端口无效');
 const targets=await localJson(`http://127.0.0.1:${port}/json/list`);
 const pages=targets.filter(t=>t.type==='page'&&t.url.startsWith('https://web.innodealing.com/dashboard/'));
 if(pages.length!==1)throw Error('DM主会话尚未就绪');
 const endpoint=new URL(pages[0].webSocketDebuggerUrl);if(!['127.0.0.1','localhost','[::1]'].includes(endpoint.hostname))throw Error('DM不是本机会话');
 const socket=new WebSocket(endpoint);
 try{
  await new Promise((res,rej)=>{const t=setTimeout(()=>rej(Error('DM连接超时')),5000);socket.addEventListener('open',()=>{clearTimeout(t);res()},{once:true});socket.addEventListener('error',()=>{clearTimeout(t);rej(Error('DM连接失败'))},{once:true});});
  const message=await new Promise((res,rej)=>{const t=setTimeout(()=>rej(Error('DM查询超时')),timeout);socket.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.id===1){clearTimeout(t);res(m);}});socket.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:`(${pageFunction.toString()})(${JSON.stringify(input)},${dmPageModules.toString()})`,awaitPromise:true,returnByValue:true}}));});
  if(message.error||message.result.exceptionDetails)throw Error(message.result?.exceptionDetails?.exception?.description?.split('\n')[0]||'DM查询失败');
  return message.result.result.value;
 }finally{socket.close();}
}
export async function readResearch(date,options){return evaluateDmPage(pageResearch,date,options);}
export async function waitForDmResearch(date,{coldStart=false,beforeAttempt=async()=>{},onRetry=async()=>{},query=readResearch,now=()=>performance.now(),sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms))}={}){
 const budget=coldStart?180000:90000,start=now();
 let last;
 while(now()-start<budget){
  await beforeAttempt();
  const remaining=budget-(now()-start);
  if(remaining<=0)break;
  try{return await query(date,{timeout:Math.min(45000,remaining)});}
  catch(error){
   if(/模块版本|返回格式|简报未找到|不是本机会话|会话端口无效|\b(?:EPERM|EACCES)\b/.test(error.message)||['EPERM','EACCES'].includes(error.code))throw error;
   last=error;
   const waiting=/ECONNREFUSED/.test(error.message)||error.code==='ENOENT'?'DM本地服务尚未启动':error.message.replace(/^Error: /,'');
   await onRetry(`等待DM（${Math.floor((now()-start)/1000)}秒 / 最多约${budget/1000}秒）：${waiting}`);
  }
  const delay=Math.min(4000,budget-(now()-start));
  if(delay>0)await sleep(delay);
 }
 const detail=last?.code==='ENOENT'?'未检测到本地会话端口':last?.message?.replace(/^Error: /,'');
 throw Error(`DM在约${budget/1000}秒内未就绪${detail?'：'+detail:''}。请正常打开DM，确认能进入行情或资讯页面后重试。`,{cause:last});
}
async function pageResearch(date,loadModules){
 const find=loadModules();
 const api=find('研究资讯查询','/onshore-sentiment-service-apple','/api/v1/web/restructure/sentiment/news/paging',(exports,route)=>{
  const queries=Object.values(exports).filter(value=>typeof value==='function'&&route(String(value)));
  const research=Object.values(exports).find(value=>Number.isInteger(value?.DmResearch))?.DmResearch;
  const internal=Object.values(exports).find(value=>Number.isInteger(value?.Internal))?.Internal;
  if(queries.length===1&&Number.isInteger(research)&&Number.isInteger(internal))return {query:queries[0],research,internal};
 });
 const [year,month,day]=date.split('-').map(Number),titleDate=`${year}年${month}月${day}`;
 const seen=new Set();let cursor={},pages=0;
 while(pages++<15){
  const r=await api.query({data:{secTagCodeSet:[],international:api.internal,pageSize:50,modelValue:api.research,...cursor}});
  if(!Array.isArray(r?.list))throw Error('DM资讯返回格式变化');
  const matches=r.list.filter(x=>(x.title||'').includes(titleDate+'信用债一级市场认购数据简报'));
  if(matches.length){const a=matches[0];return {id:a.sentimentId,title:a.title,publishedAt:a.issueTime,attachments:a.annexList||[],pages};}
  if(!r.hasNextPage)break;
  const key=r.startPageId+':'+r.endPageId;if(seen.has(key)||!r.list.length)break;seen.add(key);
  cursor={direction:true,startPageId:r.startPageId,endPageId:r.endPageId};
 }
 throw Error('目标日期DM简报未找到（已检查'+pages+'页），不使用旧日期替代');
}
export async function downloadDmArticle(article,date,directory,{fetchImpl=fetch,sleep=ms=>new Promise(r=>setTimeout(r,ms)),onRetry=async()=>{}}={}){
 const name='一级市场招标'+date.replaceAll('-','')+'.xlsx';
 const candidates=article.attachments.filter(x=>x.sentimentFileName===name);if(candidates.length!==1)throw Error('目标Excel附件缺失或不唯一');
 const u=new URL(candidates[0].sentimentFileUrl);
 if(u.protocol!=='https:'||u.hostname!=='dmdata-shanghai.oss-cn-shanghai.aliyuncs.com'||!/^\/apple\/file\/[a-f\d-]+\.xlsx$/i.test(u.pathname)||u.search||u.username||u.password)throw Error('DM附件地址不符合已验证格式');
 let bytes;
 for(let attempt=1;attempt<=3;attempt++){
  try{
   const r=await fetchImpl(u,{redirect:'error',signal:AbortSignal.timeout(30000)});
   if(!r.ok){const e=Error('HTTP '+r.status);e.retryable=r.status===408||r.status===429||r.status>=500;throw e}
   bytes=Buffer.from(await r.arrayBuffer());
   if(bytes.length>20e6||bytes[0]!==80||bytes[1]!==75){const e=Error('返回内容不是有效XLSX');e.retryable=false;throw e}
   break;
  }catch(e){
   const detail=[e.message,e.cause?.code,e.cause?.message].filter(Boolean).join(' / ');
   if(e.retryable===false||attempt===3)throw Error(`DM附件下载失败（第${attempt}次）：${detail}。请检查网络或系统代理连接。`,{cause:e});
   await onRetry(`DM附件下载暂未成功（${attempt}/3）：${detail}，稍后重试`);await sleep(attempt*2000);
  }
 }
 const file=path.join(directory,name);await fs.writeFile(file,bytes);
 return {...article,file,name,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),url:u.href};
}
