#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster
mkdir -p "$project_dir/evidence"
kubectl -n service-lab get deployment,svc,ingress,pods,resourcequota,limitrange -o yaml > "$project_dir/evidence/workload-after.yaml"
kubectl -n service-lab get ciliumnetworkpolicy,authorizationpolicy,sidecar,peerauthentication -o yaml > "$project_dir/evidence/policies.yaml"
kubectl get servicelabsecurity service-lab-security -o yaml > "$project_dir/evidence/gatekeeper-audit.yaml"
kubectl get ciliumendpoints -A > "$project_dir/evidence/cilium-endpoints.txt"
kubectl -n service-lab logs deployment/service-lab -c istio-proxy --tail=50 > "$project_dir/evidence/istio-access.log"
echo "Результаты сохранены в evidence/."
