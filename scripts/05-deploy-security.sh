#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster
kubectl get crd ciliumnetworkpolicies.cilium.io servicelabsecurity.constraints.gatekeeper.sh >/dev/null
kubectl apply -f "$project_dir/deploy/app/namespace.yaml"
kubectl apply -f "$project_dir/deploy/app/resources.yaml"
kubectl apply -f "$project_dir/deploy/policies/istio.yaml"
kubectl apply -f "$project_dir/deploy/policies/cilium.yaml"
kubectl apply -f "$project_dir/deploy/app/workload.yaml"
kubectl -n service-lab rollout status deployment/service-lab --timeout=300s
kubectl -n service-lab get pods,svc,ingress,ciliumendpoints
