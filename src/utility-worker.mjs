import {spawn}from'node:child_process';import path from'node:path';import readline from'node:readline';

// Only non-COM utilities are retained. Wind/report retain independent, owned Office workers.
export class PowerShellUtility {
 constructor(root,env=process.env){this.root=root;this.env=env;this.child=null;this.pending=new Map();this.nextId=1;this.metrics=[];}
 start(){
  if(this.child&&this.child.exitCode===null&&!this.child.killed)return this.child;
  const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(this.root,'src','utility-worker.ps1'),'-RuntimeRoot',this.root],{windowsHide:true,stdio:['pipe','pipe','pipe'],env:this.env});
  this.child=child;let stderr='';child.stderr.setEncoding('utf8');child.stderr.on('data',part=>{stderr=(stderr+part).slice(-4000)});
  const fail=error=>{for(const [id,p]of this.pending)if(p.child===child){clearTimeout(p.timer);this.pending.delete(id);p.reject(error)}};
  child.on('error',fail);child.stdin.on('error',fail);
  child.on('exit',code=>{fail(Error('PowerShell utility exited '+code+(stderr?' '+stderr:'')));if(this.child===child)this.child=null;});
  const lines=readline.createInterface({input:child.stdout});
  lines.on('line',line=>{
   let message;try{message=JSON.parse(line.replace(/^\uFEFF/,''));}catch{fail(Error('PowerShell utility returned invalid protocol'));child.kill();return;}
   const p=this.pending.get(message.id);if(!p||p.child!==child)return;
   clearTimeout(p.timer);this.pending.delete(message.id);this.metrics.push({operation:p.operation,elapsedMs:message.elapsedMs,workerPid:message.workerPid,ok:message.ok});
   if(message.ok)p.resolve(message.output);else p.reject(Error('PowerShell utility failed: '+message.error));
  });
  return child;
 }
 request(kind,parameters,timeout=120000){
  if(!['policy','xlsx'].includes(kind))return Promise.reject(Error('Unsupported utility operation'));
  const child=this.start(),id=this.nextId++;
  return new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>{this.pending.delete(id);reject(Error('PowerShell utility timed out: '+kind));child.kill();},timeout);
   this.pending.set(id,{resolve,reject,timer,child,operation:kind+':'+parameters.Mode});
   child.stdin.write(JSON.stringify({id,kind,parameters})+'\n',error=>{if(error){const p=this.pending.get(id);if(p){clearTimeout(timer);this.pending.delete(id);reject(error)}}});
  });
 }
 async close(){
  const child=this.child;if(!child||child.exitCode!==null)return;
  await new Promise(resolve=>{const timer=setTimeout(()=>{child.kill();resolve()},5000);child.once('exit',()=>{clearTimeout(timer);resolve()});child.stdin.end();});
 }
}
