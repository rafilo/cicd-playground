$ErrorActionPreference='Stop'
kubectl get nodes
kubectl get pods -n cicd-demo -l app=demo -o wide
kubectl get deployment,pdb,service -n cicd-demo
kubectl get events -n cicd-demo --field-selector type=Warning
kubectl get application cicd-demo -n argocd
kubectl get pods -n argocd
