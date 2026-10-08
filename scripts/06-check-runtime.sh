#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cluster
need python3
mkdir -p "$project_dir/evidence"
kubectl apply -f "$project_dir/checks/baseline.yaml"
kubectl apply -f "$project_dir/checks/outsider.yaml"
kubectl apply -f "$project_dir/checks/probe.yaml"
for item in 'security-baseline baseline-probe' 'security-outsider outsider-probe' 'service-lab security-probe'; do
  read -r ns pod <<< "$item"
  kubectl -n "$ns" wait --for=condition=Ready pod/"$pod" --timeout=120s
done
kubectl -n service-lab get pods -l app=service-lab -o json | python3 -c '
import json,sys
pods = [
    p for p in json.load(sys.stdin)["items"]
    if not p["metadata"].get("deletionTimestamp")
    and p["status"].get("phase") == "Running"
    and any(
        c["type"] == "Ready" and c["status"] == "True"
        for c in p["status"].get("conditions", [])
    )
]
assert len(pods)>=2, "Нет двух Pod приложения"
for p in pods:
 assert any(c["name"]=="istio-proxy" and c["ready"] for c in p["status"]["containerStatuses"]), "Istio sidecar не готов"
 assert not any(c["name"]=="istio-init" for c in p["spec"].get("initContainers",[])), "Найден привилегированный istio-init"
'
wait_endpoint service-lab security-probe
wait_endpoint security-baseline baseline-probe
wait_endpoint security-outsider outsider-probe
check_endpoints service-lab app=service-lab
# Положительный контроль исключает ложный успех из-за отсутствия интернета.
kubectl -n security-baseline exec baseline-probe -- python -c   'import socket; socket.create_connection(("1.1.1.1",443),5).close(); print("Контроль: внешний TCP доступен")'
kubectl -n service-lab exec security-probe -- python -c '
import socket
try:
 socket.create_connection(("1.1.1.1",443),5).close()
except (TimeoutError, OSError):
 print("Cilium: внешний TCP запрещён")
else:
 raise SystemExit("ОШИБКА: внешний TCP не заблокирован")
'
kubectl -n service-lab exec security-probe -- /usr/bin/ping -c 2 -W 2 77.88.8.8
kubectl -n service-lab exec security-probe -- python -c '
import urllib.request,urllib.error
base="http://service-lab.service-lab.svc.cluster.local"
checks=[("/", "POST", {"Test":"Hello"},200), ("/","POST",{},403), ("/docs","GET",{},403), ("/health","GET",{},200)]
for path,method,headers,expected in checks:
 req=urllib.request.Request(base+path,method=method,headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=8) as r: status,body=r.status,r.read().decode()
 except urllib.error.HTTPError as e: status,body=e.code,e.read().decode()
  print(method,path,status,body)
 assert status==expected,(path,status,expected)
 if expected==403:
  assert "RBAC: access denied" in body, "Запрос должен отклонить Istio, а не само приложение"
 if path=="/" and expected==200:
  assert body=="Hello, World!", body
'
# Проверяем, что посторонний клиент имеет рабочую сеть до проверки запрета.
baseline_ip=$(kubectl -n security-baseline get pod baseline-probe -o jsonpath='{.status.podIP}')
kubectl -n security-baseline exec baseline-probe -- sh -c \
  'python -m http.server 18080 --bind 0.0.0.0 >/tmp/control-http.log 2>&1 &'
kubectl -n security-outsider exec outsider-probe -- python -c '
import socket,sys,time
for attempt in range(10):
 try:
  socket.create_connection((sys.argv[1],18080),2).close()
  print("Контроль: посторонний NS имеет рабочую сеть")
  break
 except OSError:
  if attempt==9: raise
  time.sleep(1)
' "$baseline_ip"
service_ip=$(kubectl -n service-lab get service service-lab -o jsonpath='{.spec.clusterIP}')
kubectl -n security-outsider exec outsider-probe -- python -c '
import socket,sys
try:
 socket.create_connection((sys.argv[1],80),5).close()
except (TimeoutError,OSError): print("Cilium: доступ из постороннего NS запрещён")
else: raise SystemExit("ОШИБКА: посторонний NS подключился")
' "$service_ip"
kubectl -n service-lab exec -i deployment/service-lab -c app -- python - < "$project_dir/tools/check_container.py"
kubectl -n service-lab get resourcequota,limitrange
echo "Проверки выполнены. Скриншоты снимай по README. Диагностические Pod удали командой из docs/SETUP.md."