#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need python3
cd "$project_dir"
for file in scripts/*.sh; do bash -n "$file"; done
python3 tools/check_config.py
if command -v opa >/dev/null; then opa test --v0-compatible policy/ -v; fi
