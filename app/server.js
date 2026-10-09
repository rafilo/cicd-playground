import http from 'node:http';
import {fileURLToPath} from 'node:url';
let count=0;
export function createServer(){return http.createServer((req,res)=>{
count++; res.on('finish',()=>console.log(JSON.stringify({time:new Date().toISOString(),method:req.method,path:req.url,status:res.statusCode}))); res.setHeader('Content-Type','application/json');
if(req.url==='/metrics'){res.setHeader('Content-Type','text/plain; version=0.0.4');return res.end('# TYPE app_requests_total counter\napp_requests_total '+count+'\n');}
if(['/healthz','/readyz'].includes(req.url)) return res.end('{"status":"ok"}');
if(req.url==='/') return res.end(JSON.stringify({message:'Hello, GitOps!',version:process.env.APP_VERSION||'dev',pod:process.env.HOSTNAME||'local'}));
res.statusCode=404;res.end('{"error":"not found"}');
});}
if(process.argv[1]===fileURLToPath(import.meta.url)){const s=createServer().listen(8080,'0.0.0.0');for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>s.close(()=>process.exit(0)));}