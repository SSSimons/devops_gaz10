#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster; need helm
kubectl -n kube-flannel get daemonset kube-flannel-ds >/dev/null
kubectl -n kube-system get daemonset kube-proxy >/dev/null
kubectl apply -f "$project_dir/deploy/platform/cni-chain.yaml"
helm repo add cilium https://helm.cilium.io/ --force-update
helm repo update cilium
helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" -n kube-system   -f "$project_dir/deploy/platform/cilium-values.yaml" --wait --timeout 10m
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
kubectl -n kube-system exec daemonset/cilium -c cilium-agent -- cilium-dbg status --verbose
echo "Проверь новую CNI-цепочку на всех нодах, затем запусти 02-recreate-baseline.sh."
