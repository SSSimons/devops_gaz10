#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need helm
mkdir -p "$project_dir/rendered"
helm repo add cilium https://helm.cilium.io/ --force-update
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm repo update cilium gatekeeper
istio_charts
helm template cilium cilium/cilium --version "$CILIUM_VERSION" -n kube-system --kube-version 1.36.0   -f "$project_dir/deploy/platform/cilium-values.yaml" > "$project_dir/rendered/cilium.yaml"
helm template istio-base "$istio_chart_dir/base" -n istio-system --kube-version 1.36.0 --set defaultRevision=default > "$project_dir/rendered/istio-base.yaml"
helm template istiod "$istio_chart_dir/istio-control/istio-discovery" -n istio-system --kube-version 1.36.0   -f "$project_dir/deploy/platform/istiod-values.yaml" > "$project_dir/rendered/istiod.yaml"
helm template istio-cni "$istio_chart_dir/istio-cni" -n istio-system --kube-version 1.36.0   -f "$project_dir/deploy/platform/istio-cni-values.yaml" > "$project_dir/rendered/istio-cni.yaml"
helm template gatekeeper gatekeeper/gatekeeper --version "$GATEKEEPER_VERSION" -n gatekeeper-system --kube-version 1.36.0   -f "$project_dir/deploy/platform/gatekeeper-values.yaml" > "$project_dir/rendered/gatekeeper.yaml"
curl --fail --location --retry 2 --max-time 30 \
  "https://raw.githubusercontent.com/cilium/cilium/v$CILIUM_VERSION/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml" \
  -o "$project_dir/rendered/cilium-crd.yaml"
python3 "$project_dir/tools/prepare_injection.py" "$project_dir/rendered"
"$project_dir/.cache/istio-$ISTIO_VERSION/bin/istioctl" kube-inject --revision default \
  -f "$project_dir/deploy/app/workload.yaml" \
  --injectConfigFile "$project_dir/rendered/inject-config.yaml" \
  --meshConfigFile "$project_dir/rendered/mesh.yaml" \
  --valuesFile "$project_dir/rendered/inject-values.json" \
  -o "$project_dir/rendered/injected-workload.yaml"
python3 "$project_dir/tools/check_injected.py" "$project_dir/rendered"
echo "Манифесты Helm сохранены в rendered/. Это проверка шаблонов, не запуск кластера."
