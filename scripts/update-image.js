import fs from 'node:fs';
const {IMAGE,DIGEST}=process.env;
if(!/^ghcr\.io\/[a-z0-9._/-]+$/.test(IMAGE||'')||!/^sha256:[a-f0-9]{64}$/.test(DIGEST||''))throw Error('invalid image or digest');
const p='k8s/overlays/dev/kustomization.yaml';
let text=fs.readFileSync(p,'utf8');text=text.replace(/newName: .+/, 'newName: '+IMAGE).replace(/digest: .+/, 'digest: '+DIGEST);fs.writeFileSync(p,text);
