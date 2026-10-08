#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/versions.env"
need() { command -v "$1" >/dev/null || { echo "Не найдена команда: $1" >&2; exit 1; }; }
cluster() {
  need kubectl
  kubectl --request-timeout=15s get --raw=/readyz >/dev/null
}

wait_endpoint() {
  local ns="$1" pod="$2"
  for attempt in {1..30}; do
    kubectl -n "$ns" get ciliumendpoint/"$pod" >/dev/null 2>&1 && break
    sleep 2
  done
  kubectl -n "$ns" wait --for=jsonpath='{.status.identity.id}' \
    ciliumendpoint/"$pod" --timeout=120s
}

check_endpoints() {
  local ns="$1" selector="$2" names

  names=$(kubectl -n "$ns" get pods -l "$selector" -o json | python3 -c '
import json, sys

pods = json.load(sys.stdin)["items"]
print(" ".join(
    p["metadata"]["name"]
    for p in pods
    if not p["metadata"].get("deletionTimestamp")
    and p["status"].get("phase") == "Running"
    and any(
        c["type"] == "Ready" and c["status"] == "True"
        for c in p["status"].get("conditions", [])
    )
))
')

  [[ -n "$names" ]] || {
    echo "Нет готовых Pod: $ns / $selector" >&2
    return 1
  }

  for pod in $names; do
    wait_endpoint "$ns" "$pod"
  done
}

# Берём charts из закреплённого релиза: новый Helm CDN доступен не во всех сетях.
istio_charts() {
  need curl; need tar; need sha256sum
  [[ $(uname -m) == x86_64 ]] || { echo "Этот стенд рассчитан на amd64" >&2; exit 1; }
  local cache_dir="$project_dir/.cache"
  local archive="$cache_dir/istio-$ISTIO_VERSION-linux-amd64.tar.gz"
  mkdir -p "$cache_dir"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 2 --max-time 120 \
      "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux-amd64.tar.gz" \
      -o "$archive"
  fi
  printf '%s  %s\n' "$ISTIO_RELEASE_SHA256" "$archive" | sha256sum --check
  tar -xzf "$archive" -C "$cache_dir"
  istio_chart_dir="$cache_dir/istio-$ISTIO_VERSION/manifests/charts"
}
