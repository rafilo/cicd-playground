import http from 'node:http';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';

const assets = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
  '/client.js': ['client.js', 'text/javascript; charset=utf-8']
};
export function createServer({upstream = process.env.UPSTREAM_URL} = {}) {
  let count = 0;
  return http.createServer((req, res) => {
    count++;
    res.on('finish', () => console.log(JSON.stringify({time:new Date().toISOString(),method:req.method,path:req.url,status:res.statusCode})));
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'");
    const path = new URL(req.url, 'http://localhost').pathname;
    const json = (status, data) => { res.writeHead(status, {'Content-Type':'application/json'}); res.end(JSON.stringify(data)); };
    if (req.method !== 'GET') { res.setHeader('Allow','GET'); return json(405,{error:'Method not allowed'}); }
    if (path === '/healthz' || path === '/readyz') return json(200,{status:'ok'});
    if (path === '/metrics') {res.writeHead(200,{'Content-Type':'text/plain; version=0.0.4'}); return res.end('# TYPE app_requests_total counter\napp_requests_total '+count+'\n');}
    if (path === '/api/whoami') {
      if (!upstream) {
        res.setHeader('Connection','close');
        return json(200,{pod:process.env.HOSTNAME || 'local',version:process.env.APP_VERSION || 'dev',time:new Date().toISOString()});
      }
      const request = http.get(new URL('/api/whoami', upstream), {agent:false,timeout:4000,headers:{Connection:'close'}}, response => {
        let data = '';
        response.on('data', chunk => {data += chunk; if(data.length > 65536) request.destroy(new Error('Response too large'));});
        response.on('end', () => {
          if(res.writableEnded) return;
          try {
            if(response.statusCode !== 200) throw Error('Upstream failed');
            const value=JSON.parse(data);
            if(typeof value.pod !== 'string' || typeof value.version !== 'string') throw Error('Invalid response');
            json(200,value);
          } catch { json(502,{error:'Backend unavailable'}); }
        });
        response.on('error', () => {if(!res.writableEnded) json(502,{error:'Backend unavailable'});});
      });
      request.on('timeout', () => request.destroy(new Error('Upstream timeout')));
      request.on('error', () => {if(!res.writableEnded) json(502,{error:'Backend unavailable'});});
      res.on('close',()=>{if(!res.writableEnded) request.destroy();});
      return;
    }
    if (assets[path]) {
      const [file,type]=assets[path];
      res.writeHead(200,{'Content-Type':type});
      return res.end(fs.readFileSync(new URL(file,import.meta.url)));
    }
    json(404,{error:'Not found'});
  });
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const server=createServer().listen(8080,'0.0.0.0');
  for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>server.close(()=>process.exit(0)));
}
