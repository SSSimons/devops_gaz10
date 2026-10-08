#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster
need python3
# Старые Pod не получают Cilium автоматически: пересоздаём только нужные Deployment.
for item in 'kube-system coredns' 'traefik traefik' 'service-lab service-lab'; do
  read -r ns deployment <<< "$item"
  kubectl -n "$ns" rollout restart deployment/"$deployment"
  kubectl -n "$ns" rollout status deployment/"$deployment" --timeout=300s
done
check_endpoints kube-system k8s-app=kube-dns
check_endpoints traefik app.kubernetes.io/name=traefik
check_endpoints service-lab app=service-lab
kubectl get ciliumendpoints -A
