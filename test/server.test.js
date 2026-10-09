import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from '../app/server.js';
const listen=async server=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));return 'http://127.0.0.1:'+server.address().port;};
const close=server=>new Promise(r=>server.close(r));
test('Homepage, static assets, identity API, probes, and route isolation',async()=>{
 const server=createServer({upstream:''}), url=await listen(server);
 try{
  const page=await fetch(url+'/');assert.match(page.headers.get('content-type'),/text\/html/);assert.match(await page.text(),/Traffic distribution/);
  for(const asset of ['/style.css','/client.js'])assert.equal((await fetch(url+asset)).status,200);
  const response=await fetch(url+'/api/whoami');assert.equal(typeof(await response.json()).pod,'string');assert.equal(response.headers.get('connection'),'close');
  for(const p of ['/readyz','/healthz'])assert.equal((await(await fetch(url+p)).json()).status,'ok');
  assert.match(await(await fetch(url+'/metrics')).text(),/app_requests_total \d+/);
  assert.equal((await fetch(url+'/missing')).status,404);
  assert.equal((await fetch(url+'/server.js')).status,404);
  assert.equal((await fetch(url+'/',{method:'POST'})).status,405);
 }finally{await close(server);}
});
test('Web entry forwards identity requests using new upstream TCP connections',async()=>{
 const backend=createServer({upstream:''}), backendUrl=await listen(backend);
 let connections=0;backend.on('connection',()=>connections++);
 const gateway=createServer({upstream:backendUrl}), gatewayUrl=await listen(gateway);
 try{
  for(let i=0;i<4;i++){const r=await fetch(gatewayUrl+'/api/whoami');assert.equal(r.status,200);assert.equal(typeof(await r.json()).pod,'string');}
  assert.equal(connections,4);
  assert.equal((await fetch(gatewayUrl+'/')).status,200);
  await close(backend);
  assert.equal((await fetch(gatewayUrl+'/api/whoami')).status,502);
 }finally{await close(gateway);if(backend.listening)await close(backend);}
});
