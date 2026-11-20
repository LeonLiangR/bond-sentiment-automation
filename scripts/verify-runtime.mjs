import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Verify the actual installed tree, not just the files included in a hotfix.
export async function verifyRuntime(root,policy){
 const required=[...policy.runtime,...policy.templates,'一级市场情绪指数.exe','一级市场情绪指数.exe.config','runtime/node/node.exe','runtime/ChartRenderer.exe','runtime/ChartRenderer.exe.config','package.json'];
 const missing=[];
 for(const name of required)if(!(await fs.stat(path.join(root,name)).catch(()=>null))?.isFile())missing.push(name);
 const references=[];
 for(const name of policy.runtime.filter(name=>name.endsWith('.mjs'))){
  const source=await fs.readFile(path.join(root,name),'utf8').catch(()=>null);if(source===null)continue;
  for(const match of source.matchAll(/\bfrom\s*['"](\.[^'"]+)['"]|\bimport\s*\(?\s*['"](\.[^'"]+)['"]/g)){
   const target=path.resolve(root,path.dirname(name),match[1]||match[2]);
   if(!(await fs.stat(target).catch(()=>null))?.isFile())references.push(name+' -> '+path.relative(root,target));
  }
 }
 if(missing.length||references.length)throw Error('运行文件不完整：'+[...missing,...references].join('; '));
 return {passed:true,requiredFiles:required.length,modules:policy.runtime.filter(name=>name.endsWith('.mjs')).length};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const [root,policyFile]=process.argv.slice(2);
 if(!root||!policyFile)throw Error('Expected runtime directory and release-files.json');
 console.log(JSON.stringify(await verifyRuntime(path.resolve(root),JSON.parse(await fs.readFile(policyFile,'utf8')))));
}
