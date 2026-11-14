import fs from 'node:fs/promises';import path from 'node:path';import {createHash}from'node:crypto';import{localJson}from'./local-http.mjs';
export async function readResearch(date){
 const port=Number((await fs.readFile(path.join(process.env.APPDATA,'DM-Native/cache/DevToolsActivePort'),'utf8')).split(/\r?\n/)[0]);
 if(!Number.isInteger(port)||port<1||port>65535)throw Error('DM会话端口无效');
 const targets=await localJson(`http://127.0.0.1:${port}/json/list`);
 const pages=targets.filter(t=>t.type==='page'&&t.url.startsWith('https://web.innodealing.com/dashboard/'));
 if(pages.length!==1)throw Error('DM主会话尚未就绪');
 const endpoint=new URL(pages[0].webSocketDebuggerUrl);if(!['127.0.0.1','localhost','[::1]'].includes(endpoint.hostname))throw Error('DM不是本机会话');
 const socket=new WebSocket(endpoint);
 try{
  await new Promise((res,rej)=>{const t=setTimeout(()=>rej(Error('DM连接超时')),5000);socket.addEventListener('open',()=>{clearTimeout(t);res()},{once:true});socket.addEventListener('error',()=>{clearTimeout(t);rej(Error('DM连接失败'))},{once:true});});
  const message=await new Promise((res,rej)=>{const t=setTimeout(()=>rej(Error('DM查询超时')),45000);socket.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.id===1){clearTimeout(t);res(m);}});socket.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:`(${pageResearch.toString()})(${JSON.stringify(date)})`,awaitPromise:true,returnByValue:true}}));});
  if(message.error||message.result.exceptionDetails)throw Error(message.result?.exceptionDetails?.exception?.description?.split('\n')[0]||'DM查询失败');
  return message.result.result.value;
 }finally{socket.close();}
}
async function pageResearch(date){
 const w=Array.from(document.querySelectorAll('iframe')).map(f=>f.contentWindow).find(w=>{try{return w.location.origin==='https://web.innodealing.com'&&w.location.pathname==='/quote-web/';}catch{return false;}});
 if(!w?.webpackChunkdmWeb)throw Error('DM数据会话尚未就绪');
 let req;w.webpackChunkdmWeb.push([['sentiment_read_'+Date.now()],{},r=>req=r]);
 if(!req.m[389212]||!req.m[858726])throw Error('DM模块版本已变化');
 const api=req(389212),[year,month,day]=date.split('-').map(Number),titleDate=`${year}年${month}月${day}`;
 const seen=new Set();let cursor={},pages=0;
 while(pages++<15){
  const r=await api.Kv({data:{secTagCodeSet:[],international:api.N_.Internal,pageSize:50,modelValue:api.qJ.DmResearch,...cursor}});
  if(!Array.isArray(r.list))throw Error('DM资讯返回格式变化');
  const matches=r.list.filter(x=>(x.title||'').includes(titleDate+'信用债一级市场认购数据简报'));
  if(matches.length){const a=matches[0];return {id:a.sentimentId,title:a.title,publishedAt:a.issueTime,attachments:a.annexList||[],pages};}
  if(!r.hasNextPage)break;
  const key=r.startPageId+':'+r.endPageId;if(seen.has(key)||!r.list.length)break;seen.add(key);
  cursor={direction:true,startPageId:r.startPageId,endPageId:r.endPageId};
 }
 throw Error('目标日期DM简报未找到（已检查'+pages+'页），不使用旧日期替代');
}
export async function downloadDmArticle(article,date,directory){
 const name='一级市场招标'+date.replaceAll('-','')+'.xlsx';
 const candidates=article.attachments.filter(x=>x.sentimentFileName===name);if(candidates.length!==1)throw Error('目标Excel附件缺失或不唯一');
 const u=new URL(candidates[0].sentimentFileUrl);
 if(u.protocol!=='https:'||u.hostname!=='dmdata-shanghai.oss-cn-shanghai.aliyuncs.com'||!/^\/apple\/file\/[a-f\d-]+\.xlsx$/i.test(u.pathname)||u.search||u.username||u.password)throw Error('DM附件地址不符合已验证格式');
 const r=await fetch(u,{redirect:'error',signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error('DM附件下载失败 '+r.status);
 const bytes=Buffer.from(await r.arrayBuffer());if(bytes.length>20e6||bytes[0]!==80||bytes[1]!==75)throw Error('DM附件不是有效XLSX');
 const file=path.join(directory,name);await fs.writeFile(file,bytes);
 return {...article,file,name,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),url:u.href};
}
