import fs from 'node:fs/promises';

// History is chart/report context only. Daily scoring never reads this module.
export function normalizeHistory(records){
 if(!Array.isArray(records))throw Error('历史数据格式错误：需要日期记录数组');
 return records.map(record=>{
  const date=record?.date;
  if(typeof date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date+'T00:00:00Z'))||new Date(date+'T00:00:00Z').toISOString().slice(0,10)!==date)throw Error('历史日期无效');
  const {bins,index,oldIndex,n}=record;
  if(!Array.isArray(bins)||bins.length!==6||bins.some(v=>v!==null&&(!Number.isInteger(v)||v<0)))throw Error('历史六档只数无效：'+date);
  if([index,oldIndex].some(v=>v!==null&&(typeof v!=='number'||!Number.isFinite(v)))||n!==null&&(!Number.isInteger(n)||n<0))throw Error('历史指数或样本量无效：'+date);
  if(n!==null&&bins.every(v=>v!==null)&&bins.reduce((a,b)=>a+b,0)!==n)throw Error('历史分档数量与样本量不一致：'+date);
  if(record.text!==undefined&&record.text!==null&&typeof record.text!=='string')throw Error('历史文字格式无效：'+date);
  return {date,bins:[...bins],index,oldIndex,n,text:record.text??''};
 });
}
export function mergeHistoryRecords(...sources){
 const ledger=new Map();
 for(const source of sources)for(const row of normalizeHistory(source))ledger.set(row.date,row);
 return [...ledger.values()].sort((a,b)=>a.date.localeCompare(b.date));
}
export async function readHistoryFile(file){
 let text;try{text=await fs.readFile(file,'utf8');}catch(e){if(e.code==='ENOENT')return [];throw e;}
 try{return normalizeHistory(JSON.parse(text.replace(/^\uFEFF/,'')));}catch(e){throw Error('历史文件读取失败，原文件已保留：'+e.message,{cause:e});}
}
export async function readReportHistory(seedFile,localFile,date){
 const [seed,local]=await Promise.all([readHistoryFile(seedFile),readHistoryFile(localFile)]);
 return mergeHistoryRecords(seed,local).filter(row=>row.date<date);
}
