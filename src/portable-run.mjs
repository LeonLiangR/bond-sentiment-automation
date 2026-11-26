import fs from'node:fs/promises';import path from'node:path';import os from'node:os';import{fileURLToPath}from'node:url';import{execFile}from'node:child_process';import{promisify}from'node:util';
import{readResearch,waitForDmResearch,downloadDmArticle}from'./dm.mjs';import{connectDq}from'./dq.mjs';import{filterSamples,makeScenario,bindUploaded,calculationRows,joinResults,summarize,makeNarrative,uploadRow}from'./core.mjs';import{buildReportPlan,checkNativeReport}from'./report-plan.mjs';import{selectOffice}from'./office-config.mjs';
import{readReportHistory,readHistoryFile,mergeHistoryRecords}from'./history.mjs';
import{resolvePricingScenarios,readDmPricingTerms}from'./dm-fallback.mjs';
import{PowerShellUtility}from'./utility-worker.mjs';
const exec=promisify(execFile),ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2),arg=k=>args.includes(k)?args[args.indexOf(k)+1]:undefined,date=arg('--date');
if(!/^\d{4}-\d{2}-\d{2}$/.test(date||'')||!Number.isFinite(Date.parse(date+'T00:00:00Z'))||new Date(date+'T00:00:00Z').toISOString().slice(0,10)!==date)throw Error('请指定有效 --date YYYY-MM-DD');
const configFile=path.resolve(arg('--settings')||path.join(process.env.LOCALAPPDATA,'BondSentimentAutomation/settings.json')),settings=JSON.parse(await fs.readFile(configFile,'utf8'));
for(const k of ['dmExe','dqExe'])if(!settings[k]||!(await fs.stat(settings[k]).catch(()=>null))?.isFile())throw Error('请在软件路径设置中确认 '+k);
const office=selectOffice(settings);if(!(await fs.stat(office.exe).catch(()=>null))?.isFile())throw Error('请在设置中确认'+office.name+'安装位置');
const dataDir=path.dirname(configFile),outputBase=path.resolve(arg('--output-dir')||settings.outputDir||path.join(os.homedir(),'Desktop')),requestId=arg('--request-id')||null,uiStatusFile=arg('--ui-status'),cancelFile=arg('--cancel-file')||path.join(dataDir,'cancel.request');
const stamp=new Date().toISOString().replace(/[:.]/g,'-'),output=path.join(outputBase,'一级市场情绪指数_'+date.replaceAll('-','')+'_'+stamp),run=path.join(output,'过程数据');await fs.mkdir(run,{recursive:true});
const lock=path.join(dataDir,'run.lock');let lockOwned=false;try{const fd=await fs.open(lock,'wx');await fd.writeFile(JSON.stringify({pid:process.pid,run,date}));await fd.close();lockOwned=true;}catch{let old;try{old=JSON.parse(await fs.readFile(lock,'utf8'));process.kill(old.pid,0);}catch(e){if(old&&e.code==='ESRCH'){await fs.unlink(lock);const fd=await fs.open(lock,'wx');await fd.writeFile(JSON.stringify({pid:process.pid,run,date}));await fd.close();lockOwned=true;}}if(!lockOwned)throw Error('已有任务正在运行，请勿同时操作DQ');}
const save=(name,value)=>fs.writeFile(path.join(run,name+'.json'),JSON.stringify(value,null,2));let phase='准备',success=false,error='',data,cancelled=false;
function event(type,detail={}){console.log('@event '+JSON.stringify({type,requestId,date,run,output,...detail}));}
async function atomicJson(file,value){const pending=file+'.pending-'+process.pid;await fs.writeFile(pending,JSON.stringify(value,null,2));await fs.rename(pending,file);}
async function log(message){console.log(message);await fs.appendFile(path.join(run,'运行日志.txt'),new Date().toISOString()+' '+message+'\n');const match=message.match(/^\[(\d+)\/8\] (.+)/);if(match)event('stage',{stage:Number(match[1]),message:match[2]});}
async function timed(operation,action){const started=performance.now();let ok=false;try{const value=await action();ok=true;return value;}finally{await fs.appendFile(path.join(run,'timings.jsonl'),JSON.stringify({operation,phase,ok,elapsedMs:Math.round(performance.now()-started),at:new Date().toISOString()})+'\n').catch(()=>{});}}
async function command(exe,argv,timeout=120000,operation=path.basename(exe)){return timed(operation,async()=>{try{return(await exec(exe,argv,{windowsHide:true,encoding:'utf8',timeout,maxBuffer:12e6,env:{...process.env,SENTIMENT_OFFICE_ENGINE:office.engine,SENTIMENT_OFFICE_PATH:office.exe,SENTIMENT_WPS_PATH:settings.wpsExe||''}})).stdout.trim();}catch(e){throw Error(path.basename(exe)+'执行失败 '+(e.killed?'超时':e.code)+' '+String(e.stderr||e.message).slice(-2000));}});}
const quote=s=>"'"+String(s).replaceAll("'","''")+"'";
async function ps(name,parameters,timeout=120000){
 const file=path.join(ROOT,'src',name),common=path.join(ROOT,'src','wps-common.ps1'),json=Buffer.from(JSON.stringify(parameters)).toString('base64');
 const script=`[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$OutputEncoding=[Console]::OutputEncoding;$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';try{$source=[IO.File]::ReadAllText(${quote(file)},[Text.Encoding]::UTF8);$common=[IO.File]::ReadAllText(${quote(common)},[Text.Encoding]::UTF8);$source=$source.Replace(". (Join-Path \`$PSScriptRoot 'wps-common.ps1')",$common);$values=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${json}'))|ConvertFrom-Json;$parameters=@{};foreach($p in $values.PSObject.Properties){$parameters[$p.Name]=$p.Value};& ([scriptblock]::Create($source)) @parameters}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}`;
 return command('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],timeout,name+':'+(parameters.Mode||''));
}
const utility=new PowerShellUtility(ROOT,{...process.env,SENTIMENT_OFFICE_ENGINE:office.engine,SENTIMENT_OFFICE_PATH:office.exe,SENTIMENT_WPS_PATH:settings.wpsExe||''});
async function xlsx(mode,file,input,output){const parameters={Mode:mode,File:file,OutputFile:output};if(input)parameters.InputFile=input;return timed('xlsx:'+mode,()=>utility.request('xlsx',parameters));}
let needsHide=true;
async function windows(mode){if(mode==='hide'&&!needsHide)return {};return JSON.parse(await timed('process-policy.ps1:'+mode,()=>utility.request('policy',{Mode:mode,RunDirectory:run,SettingsFile:configFile},30000)));}
async function canceled(){try{await fs.access(cancelFile);throw Error('用户请求停止');}catch(e){if(e.code!=='ENOENT')throw e;}}
const replay=arg('--replay');
try{
 let dmColdStart=false;
 if(!args.includes('--cancel-file'))await fs.unlink(cancelFile).catch(()=>{});await canceled();await log('[1/8] 记录软件初始状态，业务日期 '+date);await windows('capture');await log('保留原已开启的软件；仅管理本轮新增的后台进程');if(!replay){const started=await windows('start');dmColdStart=!!started.policy.dm.launchedByRun;needsHide=dmColdStart||!!started.policy.dq.launchedByRun;}else{needsHide=false;}
 phase='DM下载';await log('[2/8] 获取DM简报及完整原始底表');let article,raw;
 if(replay){article=JSON.parse(await fs.readFile(path.join(replay,'dm-article.json'),'utf8'));article.file=path.join(replay,article.name);}
 else{article=await waitForDmResearch(date,{coldStart:dmColdStart,beforeAttempt:async()=>{await canceled();await windows('hide');await canceled();},query:(day,options)=>timed('dm:research',()=>readResearch(day,options)),onRetry:log});await canceled();await save('dm-article-metadata',article);await log('DM会话已就绪，已找到指定日期简报，开始下载附件');article=await timed('dm:download',()=>downloadDmArticle(article,date,run,{onRetry:log}));}
 if(article.name!=='一级市场招标'+date.replaceAll('-','')+'.xlsx')throw Error('DM附件日期不一致');if(replay){const copied=path.join(run,article.name);await fs.copyFile(article.file,copied);article.file=copied;}await save('dm-article',article);
 const rawFile=path.join(run,'dm-rows.json');await xlsx('extract',article.file,null,rawFile);raw=JSON.parse(await fs.readFile(rawFile,'utf8'));
 if(!raw.title.includes(Number(date.slice(5,7))+'月'+Number(date.slice(8,10))+'日'))throw Error('DM底表日期不一致');
 const {samples:sampleA,excluded:dmExcluded}=filterSamples(raw.rows,date);if(!sampleA.length)throw Error('初筛后没有有效样本');await save('sample-a',sampleA);event('service',{service:'dm',state:replay?'replay':'verified'});event('samples',{raw:raw.rows.length,sampleA:sampleA.length});await log(`DM原始${raw.rows.length}条；筛选后样本A ${sampleA.length}条`);await canceled();
 phase='Wind条款';await log('[3/8] 后台'+office.name+'运行Wind函数');let wind;
 if(replay)wind=JSON.parse(await fs.readFile(path.join(replay,'wind.json'),'utf8'));
 else{let windError;try{await ps('wind.ps1',{InputFile:path.join(run,'sample-a.json'),OutputFile:path.join(run,'wind.json')},360000);}catch(e){windError=e.message;await canceled();await log('Wind取数未完成，将用DM重新生成条款：'+windError);}
  wind=windError?sampleA.map(s=>({sampleId:s.sampleId,name:s.name,windFailure:windError})):JSON.parse(await fs.readFile(path.join(run,'wind.json'),'utf8'));}
 const terms=await resolvePricingScenarios(sampleA,wind,raw,async samples=>{
  await canceled();await log('Wind未取得有效条款 '+samples.length+'只，整条改用DM生成：'+samples.map(s=>s.name).join('、'));
  if(replay){return JSON.parse(await fs.readFile(path.join(replay,'dm-fallback.json'),'utf8')).map(r=>r.record);}
  return timed('dm:pricing-terms',()=>readDmPricingTerms(samples));
 });
 const {scenarios}=terms,excluded=[...dmExcluded,...terms.excluded];await save('dm-fallback',terms.audit);
 for(const row of wind.filter(r=>r.windRetry)){const accepted=scenarios.some(s=>s.sampleId===row.sampleId&&s.dataSource!=='DM');await log('Wind简称重试'+(accepted?'成功':'未取得原券有效条款')+'：'+row.name+' → '+row.windRetry.queryName);}
 for(const item of terms.audit)await log(item.success?'DM补全成功：'+item.name+(item.scenario.dm.themeDefaulted?'；主题字段为空，按非主题债处理':''):'DM补全失败，排除该券：'+item.name+'；'+item.error);
 if(!scenarios.length)throw Error('Wind及DM均未取得可提交条款');await save('wind',wind);await save('scenarios',scenarios);if(scenarios.some(s=>s.dataSource!=='DM'))event('service',{service:'wind',state:replay?'replay':'verified'});event('samples',{dqInput:scenarios.length});await canceled();
 phase='DQ试算';await log('[4/8] 核对DQ权限并准备批量试算，共'+scenarios.length+'条');let dq;
 if(!replay){for(let i=0;i<12;i++){await windows('hide');try{dq=await timed('dq:connect',()=>connectDq(settings));break;}catch(e){if(i===11)throw e;await log('等待DQ会话：'+e.message);await new Promise(r=>setTimeout(r,3000));}}}
 if(dq){const request=dq.request;dq.request=(endpoint,...parameters)=>timed('dq:'+endpoint.split('?')[0],()=>request(endpoint,...parameters));}
 event('service',{service:'dq',state:replay?'replay':'verified'});const limit=replay?80:Math.min(dq.limit,80),valid=[];await log('[5/8] DQ计算、下载及一一匹配校验');
 for(let offset=0;offset<scenarios.length;offset+=limit){await canceled();const batch=scenarios.slice(offset,offset+limit),number=Math.floor(offset/limit)+1,prefix='dq-batch-'+number;let bindings,results;
  if(replay){bindings=JSON.parse(await fs.readFile(path.join(replay,prefix+'-bindings.json'),'utf8'));results=JSON.parse(await fs.readFile(path.join(replay,prefix+'-results.json'),'utf8'));await fs.copyFile(path.join(replay,prefix+'-raw-result.xlsx'),path.join(run,prefix+'-raw-result.xlsx'));}
  else{
   const input=path.join(run,prefix+'-upload-rows.json'),upload=path.join(run,prefix+'-upload.xlsx');await fs.writeFile(input,JSON.stringify(batch.map((s,i)=>uploadRow(s,i+1))));await xlsx('upload',path.join(ROOT,'templates/dq-upload.xlsx'),input,upload);
   if((await fs.stat(upload)).size>51200)throw Error('DQ上传文件超过50KB');const form=new FormData();form.append('templateType','05');form.append('file',new Blob([await fs.readFile(upload)],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),path.basename(upload));await save(prefix+'-upload-response',await dq.request('search/calcPricingBatch/newUpload',form));
   const general=(await dq.request('search/calcPricingBatch/newYbFxrList',{})).data;await save(prefix+'-uploaded',general);
   const financial=(await dq.request('search/calcPricingBatch/newOtherFxrList',{})).data;if(financial.length)throw Error('DQ方案进入其他类型，请核对');bindings=bindUploaded(batch,general);
   for(const binding of bindings)if(binding.failureReason)await log('DQ定价失败，跳过：'+batch[binding.seq-1].name+'；'+binding.failureReason);
   const rows=calculationRows(general,bindings);if(rows.length){await dq.request('api/user/functionMenu/v2/issuerBatchCalculate?size='+rows.length,undefined,'GET');await dq.request('search/calcPricingBatch/calcPricingRange',{batches:rows});}
   results=(await dq.request('search/calcPricingBatch/newYbFxrList',{})).data;await dq.request('api/user/functionMenu/v2/issuerBatchCalDownload',undefined,'GET');await fs.writeFile(path.join(run,prefix+'-raw-result.xlsx'),await dq.request('search/calcPricingBatch/newIssueBatchCalDownload',[{templateType:'05'},{templateType:'05'}],'POST',true));
  }
  await save(prefix+'-bindings',bindings);await save(prefix+'-results',results);const joined=joinResults(batch,bindings,results,date);valid.push(...joined.valid);excluded.push(...joined.excluded);await log(`DQ第${number}批：有效${joined.valid.length}，排除${joined.excluded.length}`);
 }
 phase='指数计算';await log('[6/8] 计算逐券利差、得分及当日情绪指数');valid.sort((a,b)=>a.sourceRow-b.sourceRow);const summary=summarize(valid),history=await readReportHistory(path.join(ROOT,'assets','history-seed.json'),path.join(dataDir,'history.json'),date);
 data={date,valid,sampleA,excluded,summary,raw,article,history,reportText:makeNarrative(date,summary)};const plan=buildReportPlan(data);data.history=plan.historyObjects;await save('result',data);await save('report-plan',plan);await canceled();
 phase='报表输出';await log('[7/8] 生成五个sheet、文字与图片，并在'+office.name+'核验公式');const compact=date.replaceAll('-',''),image=path.join(output,'汇报图片_'+compact+'.png'),file=path.join(output,'当日报告_'+compact+'.xlsx');
 await command(path.join(ROOT,'runtime','ChartRenderer.exe'),['--plot',path.join(run,'result.json'),image],120000,'plot');
 const prepared=path.join(run,'prepared-report.xlsx');await xlsx('report',path.join(ROOT,'templates/report-five.xlsx'),path.join(run,'report-plan.json'),prepared);
 await ps('wps-report.ps1',{Template:prepared,PlanFile:path.join(run,'report-plan.json'),ImageFile:image,OutputFile:file,RunDirectory:run,PreviewPdf:args.includes('--preview-pdf')},300000);
 const actual=JSON.parse(await fs.readFile(path.join(run,'native-report.json'),'utf8')),verification=checkNativeReport(actual,data,plan);await save('verification',verification);await fs.writeFile(path.join(output,'汇报文字_'+compact+'.txt'),data.reportText+'\n');await canceled();success=true;
}catch(e){error=e.message;cancelled=error==='用户请求停止';event(cancelled?'cancelling':'failure',{message:error,phase});await log((cancelled?'任务停止：':'任务失败：')+error);}
finally{
 await log('[8/8] 释放本轮后台实例，保留原有软件');let cleanup;try{cleanup=await windows('cleanup');await save('cleanup',cleanup);if(!cleanup.clean){success=false;error+=' 本轮新增进程释放未完成';}}catch(e){success=false;error+=' 清理失败：'+e.message;}
 await utility.close();await save('utility-timings',utility.metrics);
 if(success){try{const previous=await readHistoryFile(path.join(dataDir,'history.json')),ledger=mergeHistoryRecords(previous,data.history),tmp=path.join(dataDir,'history.pending');await fs.writeFile(tmp,JSON.stringify(ledger,null,2));await fs.rename(tmp,path.join(dataDir,'history.json'));}catch(e){success=false;error+=' 历史记录保存失败：'+e.message;}}
 const status={requestId,date,success,cancelled,error,output,run,officeEngine:office.engine,summary:data?.summary,sampleACount:data?.sampleA.length,cleanup:cleanup?.clean,finishedAt:new Date().toISOString(),replay:!!replay};await save('final-status',status);await atomicJson(path.join(dataDir,'last-run.json'),status);if(success)await atomicJson(path.join(dataDir,'last-success.json'),status);if(uiStatusFile)await atomicJson(uiStatusFile,status);if(lockOwned)await fs.unlink(lock).catch(()=>{});await log(success?'完成：'+output:cancelled?'已停止：本轮后台实例已释放':'未完成：'+error);console.log(JSON.stringify(status));process.exitCode=success?0:1;
}
