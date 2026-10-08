#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need docker
cd "$project_dir"
docker build -t "$APP_IMAGE" .
docker save -o /tmp/service-lab-security.tar "$APP_IMAGE"
echo "Импортируй /tmp/service-lab-security.tar на все три ноды в namespace containerd k8s.io."
