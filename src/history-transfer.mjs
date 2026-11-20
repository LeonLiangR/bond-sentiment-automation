import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {normalizeHistory,mergeHistoryRecords,readHistoryFile} from './history.mjs';

const FORMAT='bond-sentiment-history',VERSION=1;
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
export function parseHistoryTransfer(value){
 let records;
 if(Array.isArray(value))records=value;
 else if(value?.format===FORMAT&&value.version===VERSION&&Array.isArray(value.records))records=value.records;
 else throw Error('不是受支持的历史交接文件，请选择本软件导出的JSON文件。');
 const unique=new Map();let duplicates=0;
 for(const row of normalizeHistory(records)){
  const previous=unique.get(row.date);
  if(previous){if(!equal(previous,row))throw Error('交接文件在'+row.date+'存在不同记录，未导入任何数据。');duplicates++;}
  else unique.set(row.date,row);
 }
 if(!unique.size)throw Error('交接文件没有历史记录。');
 return{records:[...unique.values()].sort((a,b)=>a.date.localeCompare(b.date)),duplicates};
}
function summary(records){return{count:records.length,firstDate:records[0]?.date||null,lastDate:records.at(-1)?.date||null};}
export async function historySummary(seedFile,localFile){return summary(mergeHistoryRecords(await readHistoryFile(seedFile),await readHistoryFile(localFile)));}
async function atomicJson(file,value){
 await fs.mkdir(path.dirname(file),{recursive:true});const pending=file+'.pending-'+randomUUID();
 try{await fs.writeFile(pending,JSON.stringify(value,null,2)+'\n',{encoding:'utf8',flag:'wx'});await fs.rename(pending,file);}
 finally{await fs.unlink(pending).catch(e=>{if(e.code!=='ENOENT')throw e;});}
}
function within(file,directory){if(!directory)return false;const relative=path.relative(path.resolve(directory),path.resolve(file));return relative===''||relative!=='..'&&!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative);}
export async function exportHistory({seedFile,localFile,outputFile,dataDir,rootDir}){
 if(within(outputFile,dataDir)||within(outputFile,rootDir))throw Error('请将交接文件保存到桌面或其他工作目录，不要覆盖软件及配置目录。');
 const records=mergeHistoryRecords(await readHistoryFile(seedFile),await readHistoryFile(localFile));
 if(!records.length)throw Error('尚无可导出的历史，请先生成报告或导入交接文件。');
 const coverage=summary(records);
 // normalizeHistory is an allowlist: no raw bonds, user configuration or credentials.
 await atomicJson(outputFile,{format:FORMAT,version:VERSION,exportedAt:new Date().toISOString(),coverage,records});
 return{success:true,operation:'export',...coverage,file:path.resolve(outputFile)};
}
async function acquireLock(dataDir){
 await fs.mkdir(dataDir,{recursive:true});const file=path.join(dataDir,'run.lock'),token=randomUUID();
 for(let attempt=0;attempt<2;attempt++){
  try{const handle=await fs.open(file,'wx');try{await handle.writeFile(JSON.stringify({pid:process.pid,kind:'history-transfer',token}));}finally{await handle.close();}
   return async()=>{const current=JSON.parse(await fs.readFile(file,'utf8'));if(current.token===token)await fs.unlink(file);};
  }catch(e){
   if(e.code!=='EEXIST')throw e;
   let raw,lock;try{raw=await fs.readFile(file,'utf8');lock=JSON.parse(raw);}catch{throw Error('已有任务锁，无法确认状态，请结束其他任务后再导入。');}
   if(!Number.isInteger(lock.pid)||lock.pid<=0)throw Error('任务锁状态异常，请确认其他窗口已关闭。');
   try{process.kill(lock.pid,0);}catch(error){if(error.code==='ESRCH'&&await fs.readFile(file,'utf8')===raw){await fs.unlink(file);continue;}}
   throw Error('已有报告或历史交接正在执行，请结束后再导入。');
  }
 }
 throw Error('未能取得历史导入锁，请稍后再试。');
}
export async function importHistory({seedFile,localFile,inputFile,dataDir}){
 const stat=await fs.stat(inputFile);if(!stat.isFile()||stat.size>32*1024*1024)throw Error('请选择不超过32MB的历史JSON文件。');
 let parsed;try{parsed=JSON.parse((await fs.readFile(inputFile,'utf8')).replace(/^\uFEFF/,''));}catch{throw Error('历史JSON文件无法解析，原历史未修改。');}
 const incoming=parseHistoryTransfer(parsed),release=await acquireLock(dataDir);
 try{
  const current=mergeHistoryRecords(await readHistoryFile(seedFile),await readHistoryFile(localFile)),byDate=new Map(current.map(r=>[r.date,r]));
  let added=0,identical=0;const conflicts=[];
  for(const row of incoming.records){const old=byDate.get(row.date);if(!old){byDate.set(row.date,row);added++;}else if(equal(old,row))identical++;else conflicts.push(row.date);}
  const records=[...byDate.values()].sort((a,b)=>a.date.localeCompare(b.date));let backupFile=null;
  if(added){
   let previous;try{previous=await fs.readFile(localFile);}catch(e){if(e.code!=='ENOENT')throw e;}
   if(previous){backupFile=path.join(dataDir,'history-backups','history-'+new Date().toISOString().replace(/[:.]/g,'-')+'-'+randomUUID()+'.json');await fs.mkdir(path.dirname(backupFile),{recursive:true});await fs.writeFile(backupFile,previous,{flag:'wx'});}
   await atomicJson(localFile,records);
  }
  return{success:true,operation:'import',...summary(records),added,identical,duplicates:incoming.duplicates,conflictCount:conflicts.length,conflictDates:conflicts,conflictPreview:conflicts.slice(0,12).join('、'),backupFile};
 }finally{await release();}
}

async function main(){
 const args=process.argv.slice(2),arg=k=>args.includes(k)?args[args.indexOf(k)+1]:undefined;
 const mode=arg('--mode'),rootDir=path.resolve(arg('--root')||path.join(path.dirname(fileURLToPath(import.meta.url)),'..'));
 const dataDir=arg('--data-dir');if(!dataDir)throw Error('未指定历史数据目录。');
 const options={seedFile:path.join(rootDir,'assets','history-seed.json'),localFile:path.join(path.resolve(dataDir),'history.json'),dataDir:path.resolve(dataDir),rootDir};
 let result;
 if(mode==='summary')result={success:true,...await historySummary(options.seedFile,options.localFile)};
 else if(mode==='export'&&arg('--file'))result=await exportHistory({...options,outputFile:path.resolve(arg('--file'))});
 else if(mode==='import'&&arg('--file'))result=await importHistory({...options,inputFile:path.resolve(arg('--file'))});
 else throw Error('历史交接操作或文件参数无效。');
 console.log(JSON.stringify(result));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(e=>{console.error(e.message);process.exitCode=1;});
