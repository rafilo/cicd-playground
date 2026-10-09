import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const script=path.resolve('scripts/update-image.js');
test('镜像摘要更新及拒绝无效输入',()=>{
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'gitops-'));
 try{
  fs.mkdirSync(path.join(temp,'k8s/overlays/dev'),{recursive:true});
  const p=path.join(temp,'k8s/overlays/dev/kustomization.yaml');
  const source=fs.readFileSync('k8s/overlays/dev/kustomization.yaml','utf8');
  fs.writeFileSync(p,source);
  const digest='sha256:'+'a'.repeat(64);
  let result=spawnSync(process.execPath,[script],{cwd:temp,env:{...process.env,IMAGE:'ghcr.io/example/demo',DIGEST:digest}});
  assert.equal(result.status,0,result.stderr?.toString());
  const updated=fs.readFileSync(p,'utf8');
  assert.ok(updated.includes('newName: ghcr.io/example/demo'));assert.ok(updated.includes('digest: '+digest));assert.ok(updated.includes('resources: [../../base]'));
  result=spawnSync(process.execPath,[script],{cwd:temp,env:{...process.env,IMAGE:'invalid',DIGEST:'latest'}});
  assert.notEqual(result.status,0);assert.equal(fs.readFileSync(p,'utf8'),updated);
 }finally{fs.rmSync(temp,{recursive:true,force:true});}
});
