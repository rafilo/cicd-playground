import fs from 'node:fs';import assert from 'node:assert/strict';
const read=p=>fs.readFileSync(p,'utf8');
const d=read('k8s/base/deployment.yaml');assert.match(d,/replicas: 3/);for(const s of ['readinessProbe:','livenessProbe:','requests:','limits:','maxUnavailable: 0','maxSurge: 1'])assert.ok(d.includes(s),s);
assert.match(read('k8s/base/pdb.yaml'),/minAvailable: 2/);
const a=read('argocd/application.yaml');for(const s of ['prune: true','selfHeal: true','enabled: true'])assert.ok(a.includes(s));
const w=read('.github/workflows/ci.yaml');assert.ok(!/kubectl (apply|set|rollout)/.test(w));assert.ok(w.includes('pull_request:'));assert.match(read('k8s/overlays/dev/kustomization.yaml'),/digest: sha256:[a-f0-9]{64}/);console.log('Configuration contract checks passed; also run kubectl kustomize and an API dry-run.');
