#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
for name in writable-root quota limit; do
  if kubectl create --dry-run=server -f "$project_dir/checks/negative/$name.yaml" >"$work_dir/$name.log" 2>&1; then
    echo "ОШИБКА: запрещённый Pod $name был принят" >&2; exit 1
  fi
  cat "$work_dir/$name.log"
  case "$name" in
    writable-root) grep -q 'service-lab-security' "$work_dir/$name.log" ;;
    quota) grep -q 'exceeded quota' "$work_dir/$name.log" ;;
    limit) grep -Eq 'maximum cpu|maximum.*cpu' "$work_dir/$name.log" ;;
  esac
done
# PSA restricted независимо отклоняет root/privileged/hostPath.
for name in root privileged hostpath; do
  if kubectl create --dry-run=server -f "$project_dir/checks/negative/$name.yaml" >"$work_dir/$name.log" 2>&1; then
    echo "ОШИБКА: Pod $name был принят" >&2; exit 1
  fi
  cat "$work_dir/$name.log"
  grep -Eq 'PodSecurity|service-lab-security' "$work_dir/$name.log"
done
echo "Admission: запрещённые Pod отклонены; dry-run ничего не создал."
