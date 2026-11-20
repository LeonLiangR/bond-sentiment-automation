import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';
import {verifyRuntime}from '../scripts/verify-runtime.mjs';
test('运行目录核验同时检查完整清单和已安装入口的相对依赖',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'sentiment-runtime-'));
 try{
  await fs.mkdir(path.join(dir,'src'));await fs.mkdir(path.join(dir,'runtime/node'),{recursive:true});
  for(const file of ['一级市场情绪指数.exe','一级市场情绪指数.exe.config','runtime/node/node.exe','runtime/ChartRenderer.exe','runtime/ChartRenderer.exe.config','package.json'])await fs.writeFile(path.join(dir,file),'fixture');
  await fs.writeFile(path.join(dir,'src/main.mjs'),"import{read}from'./history.mjs';");
  const policy={runtime:['src/main.mjs'],templates:[]};
  await assert.rejects(verifyRuntime(dir,policy),/main\.mjs -> src[\\/]history\.mjs/);
  policy.runtime.push('src/history.mjs');await assert.rejects(verifyRuntime(dir,policy),/src\/history\.mjs/);
  await fs.writeFile(path.join(dir,'src/history.mjs'),'export function read(){}');
  assert.equal((await verifyRuntime(dir,policy)).passed,true);
 }finally{await fs.rm(dir,{recursive:true,force:true});}
});
