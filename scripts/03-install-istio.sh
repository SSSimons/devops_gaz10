#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster; need helm
istio_charts
helm upgrade --install istio-base "$istio_chart_dir/base" -n istio-system \
  --create-namespace --set defaultRevision=default --wait --timeout 5m
helm upgrade --install istio-cni "$istio_chart_dir/istio-cni" -n istio-system \
  -f "$project_dir/deploy/platform/istio-cni-values.yaml" --wait --timeout 5m
helm upgrade --install istiod "$istio_chart_dir/istio-control/istio-discovery" -n istio-system \
  -f "$project_dir/deploy/platform/istiod-values.yaml" --wait --timeout 5m
kubectl -n istio-system get pods
