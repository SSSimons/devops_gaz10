#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster; need helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm repo update gatekeeper
helm upgrade --install gatekeeper gatekeeper/gatekeeper --version "$GATEKEEPER_VERSION"   -n gatekeeper-system --create-namespace -f "$project_dir/deploy/platform/gatekeeper-values.yaml"   --wait --timeout 5m
kubectl apply -f "$project_dir/deploy/gatekeeper/template.yaml"
# Controller создаёт CRD асинхронно, ждём появления перед kubectl wait.
for attempt in {1..30}; do
  kubectl get crd/servicelabsecurity.constraints.gatekeeper.sh >/dev/null 2>&1 && break
  sleep 2
done
kubectl wait --for=condition=Established crd/servicelabsecurity.constraints.gatekeeper.sh --timeout=120s
kubectl apply -f "$project_dir/deploy/gatekeeper/constraint.yaml"
kubectl -n gatekeeper-system get pods
