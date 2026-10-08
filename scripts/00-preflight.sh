#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster; need helm; need python3
if command -v snap >/dev/null && snap services microk8s 2>/dev/null | awk 'NR>1 {print $3}' | grep -qx active; then
  echo "На этой ноде запущен MicroK8s. Для kubeadm-стенда останови его: sudo snap stop --disable microk8s" >&2
  exit 1
fi
kubectl get nodes -o wide
kubectl wait --for=condition=Ready nodes --all --timeout=60s
kubectl -n kube-flannel get daemonset kube-flannel-ds
kubectl -n traefik get deployment traefik
kubectl -n service-lab rollout status deployment/service-lab --timeout=60s
kubectl -n service-lab get networkpolicy -o json | python3 -c '
import json,sys
assert not json.load(sys.stdin)["items"], "Обнаружены прежние NetworkPolicy. Сначала проверь их совместимость с новой политикой."
'
kubectl get nodes -o json | python3 -c '
import sys,json
nodes=json.load(sys.stdin)["items"]
assert len(nodes)==3, "Ожидаются три ноды"
for node in nodes:
 assert node["status"]["nodeInfo"]["kubeletVersion"].startswith("v1.36."), "Нужен Kubernetes v1.36"
'
mkdir -p "$project_dir/evidence"
kubectl -n service-lab get deployment,service,ingress -o yaml > "$project_dir/evidence/baseline-workload.yaml"
kubectl get nodes -o wide > "$project_dir/evidence/nodes-before.txt"
echo "Исходный стенд доступен. Сохрани VMware snapshots и резервные копии CNI на нодах по docs/SETUP.md."
