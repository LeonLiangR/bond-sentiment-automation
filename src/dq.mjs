import fs from 'node:fs/promises';import os from 'node:os';import crypto from 'node:crypto';import path from 'node:path';
import{localJson}from'./local-http.mjs';
const ALLOWED=new Set(['search/primaryMarketPricing/getAuth','search/calcPricingBatch/getmaxLength','search/calcPricingBatch/queryBatchCalDownloadRole','search/calcPricingBatch/newUpload','search/calcPricingBatch/newYbFxrList','search/calcPricingBatch/newOtherFxrList','search/calcPricingBatch/calcPricingRange','search/calcPricingBatch/newIssueBatchCalDownload','api/user/functionMenu/v2/issuerBatchCalculate','api/user/functionMenu/v2/issuerBatchCalDownload']);
export async function connectDq(settings){
 const mac=Object.values(os.networkInterfaces()).flat().find(x=>x.mac!=='00:00:00:00:00:00')?.mac;if(!mac)throw Error('未找到本机网卡');
 const info=await localJson('http://127.0.0.1:5001/getDQLoginInfo?mac='+mac);
 if(!info.authorization)throw Error('DQ登录会话尚未就绪');
 const app=await fs.readFile(path.join(path.dirname(settings.dqExe),'resources/app.asar.unpacked/dist/electron/main.js'),'utf8');
 const key=app.match(/'([a-f0-9]{32})'/)?.[1],iv=app.match(/'([a-f0-9]{16})'/)?.[1];if(!key||!iv)throw Error('DQ登录态接口版本变化');
 const dec=crypto.createDecipheriv('aes-256-cbc',key,iv),authorization=dec.update(info.authorization,'hex','utf8')+dec.final('utf8');
 async function request(endpoint,body,method='POST',binary=false){
  if(!ALLOWED.has(endpoint.split('?')[0]))throw Error('不允许的DQ操作');
  const headers={Authorization:authorization,Version:settings.dqVersion||'1.131.1',Accept:'*/*'};if(body&&!(body instanceof FormData))headers['Content-Type']='application/json;charset=UTF-8';
  const r=await fetch('https://quant.chinabond.com.cn/'+endpoint,{method,headers,body:body instanceof FormData?body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(180000)});
  if(binary){const bytes=Buffer.from(await r.arrayBuffer());if(bytes[0]!==80||bytes[1]!==75)throw Error('DQ下载未返回XLSX：'+bytes.toString('utf8').slice(0,150));return bytes;}
  let result;try{result=await r.json();}catch{throw Error('DQ返回非JSON，HTTP '+r.status);}
  if(!r.ok||result.code&&result.code!=='S00000000001')throw Error('DQ请求失败：'+(result.msg||result.code||r.status));
  return {message:result.msg,data:result.code==='S00000000001'?result.data:result};
 }
 const rights=await request('search/primaryMarketPricing/getAuth',{channel:'PC'});
 if(rights.data?.pricingDataIntercept!=='00')throw Error('当前DQ账号没有批量试算权限');
 const download=await request('search/calcPricingBatch/queryBatchCalDownloadRole',undefined,'GET');if(download.data!=='1')throw Error('当前DQ账号没有结果下载权限');
 const limit=Number((await request('search/calcPricingBatch/getmaxLength',{})).data?.paravalue);
 if(!Number.isInteger(limit)||limit<=0)throw Error('DQ批量上限无效');
 return {request,limit};
}
