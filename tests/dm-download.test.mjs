import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';
import {dmPageModules,downloadDmArticle,waitForDmResearch} from '../src/dm.mjs';
const article={attachments:[{sentimentFileName:'一级市场招标20261113.xlsx',sentimentFileUrl:'https://dmdata-shanghai.oss-cn-shanghai.aliyuncs.com/apple/file/12345678-abcd.xlsx'}]};

test('DM模块编号变化后按精确路径识别，不执行其他服务或相似路径',()=>{
 const expected=()=>'/api/search/gathering';
 const modules={
  17:()=>['/onshore-bond-basic','/api/search/gathering'],
  31:()=>['/onshore-search-service','/api/search/gathering/partySearch'],
  142387:()=>['/onshore-search-service','/api/search/gathering']
 };
 const loaded=[];
 const runtime=Object.assign(id=>{loaded.push(id);return {renamed:expected};},{m:modules});
 const page={querySelectorAll:()=>[{contentWindow:{location:{origin:'https://web.innodealing.com',pathname:'/quote-web/'},webpackChunkdmWeb:{push:chunk=>chunk[2](runtime)}}}]};
 const find=()=>dmPageModules(page)('个券搜索','/onshore-search-service','/api/search/gathering',(exports,route)=>Object.values(exports).find(value=>route(String(value))));
 assert.equal(find(),expected);assert.deepEqual(loaded,['142387']);
 modules[99]=modules[142387];
 assert.throws(find,/无法唯一识别个券搜索/);assert.equal(loaded.length,1);
});
test('网络短暂断开后重试，成功文件内容不变',async()=>{const dir=await fs.mkdtemp(path.join(os.tmpdir(),'dm-download-'));let calls=0;const logs=[];try{const result=await downloadDmArticle(article,'2026-11-13',dir,{sleep:async()=>{},onRetry:async m=>logs.push(m),fetchImpl:async()=>{if(++calls<3)throw new TypeError('fetch failed',{cause:Object.assign(Error('socket reset'),{code:'ECONNRESET'})});return new Response(new Uint8Array([80,75,3,4]));}});assert.equal(calls,3);assert.equal(logs.length,2);assert.equal(result.bytes,4);assert.deepEqual([...await fs.readFile(result.file)],[80,75,3,4]);}finally{await fs.rm(dir,{recursive:true,force:true});}});
test('下载重试耗尽显示底层原因；权限错误不重复请求',async()=>{let calls=0;await assert.rejects(downloadDmArticle(article,'2026-11-13',os.tmpdir(),{sleep:async()=>{},fetchImpl:async()=>{calls++;throw new TypeError('fetch failed',{cause:Object.assign(Error('connection refused'),{code:'ECONNREFUSED'})});}}),/第3次.*ECONNREFUSED/);assert.equal(calls,3);calls=0;await assert.rejects(downloadDmArticle(article,'2026-11-13',os.tmpdir(),{sleep:async()=>{},fetchImpl:async()=>{calls++;return new Response('',{status:403});}}),/HTTP 403/);assert.equal(calls,1);});
test('无效附件不可落盘，校验失败不重试',async()=>{let calls=0;await assert.rejects(downloadDmArticle(article,'2026-11-13',os.tmpdir(),{fetchImpl:async()=>{calls++;return new Response('error page');}}),/有效XLSX/);assert.equal(calls,1);});

test('DM冷启动超过旧版60秒仍可等到数据页就绪',async()=>{
 let elapsed=0;const logs=[];const date='2026-11-18';
 const result=await waitForDmResearch(date,{coldStart:true,now:()=>elapsed,sleep:async delay=>{elapsed+=delay;},onRetry:async message=>logs.push(message),query:async requested=>{
  assert.equal(requested,date);
  if(elapsed<40000)throw Error('connect ECONNREFUSED 127.0.0.1:18088');
  if(elapsed<48000)throw Error('DM主会话尚未就绪');
  if(elapsed<72000)throw Error('Error: DM数据会话尚未就绪');
  return article;
 }});
 assert.equal(result,article);assert.equal(elapsed,72000);
 for(const state of ['DM本地服务尚未启动','DM主会话尚未就绪','DM数据会话尚未就绪'])assert.ok(logs.some(message=>message.includes(state)));
});

test('已有DM会话仍未就绪时按上限退出，保留最后的失败阶段',async()=>{
 let elapsed=0;
 await assert.rejects(waitForDmResearch('2026-11-18',{now:()=>elapsed,sleep:async delay=>{elapsed+=delay;},query:async(_date,options)=>{
  assert.ok(options.timeout<=90000-elapsed);throw Error('DM数据会话尚未就绪');
 }}),/90秒.*DM数据会话尚未就绪/);
 assert.equal(elapsed,90000);
});

test('已读到资讯但简报缺失，以及停止任务时，不再等待DM',async()=>{
 let calls=0;const stop=Error('用户请求停止'),missing=Error('目标日期DM简报未找到');
 const query=async()=>{calls++;throw missing;};
 await assert.rejects(waitForDmResearch('2026-11-18',{query,beforeAttempt:async()=>{throw stop;}}),error=>error===stop);
 assert.equal(calls,0);
 await assert.rejects(waitForDmResearch('2026-11-18',{query,sleep:async()=>assert.fail('不应继续等待')}),error=>error===missing);
 assert.equal(calls,1);
});
