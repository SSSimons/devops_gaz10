# 🚀 Установка на существующий service-lab

Это отдельный репозиторий. Здесь нет повторного `kubeadm init`, создания VM или настройки NAT с нуля. Приложение и тесты взяты из предыдущего задания; изменения Dockerfile описаны в [BASELINE.md](BASELINE.md).

## 0. Исходный стенд

| VM | IP | Что используется |
| --- | --- | --- |
| gateway-vm | 192.168.76.254 | NAT во внешнюю сеть |
| app-vm | 192.168.76.10 | Сборка образа, предыдущие systemd/Docker/мониторинг |
| k8s-cp | 192.168.76.20 | Control-plane, kubectl, Helm |
| k8s-w1 | 192.168.76.21 | Worker |
| k8s-w2 | 192.168.76.22 | Worker |

У нод один интерфейс VMnet1, default route через `.254`. Внешний интерфейс есть только у шлюза. Pod CIDR `10.244.0.0/16`, Service CIDR `10.96.0.0/12`, Kubernetes `1.36.x`, Flannel `v0.28.9`. Traefik уже установлен в namespace `traefik`, с Deployment `traefik` и NodePort `30080`.

Для лаборатории выдели каждой K8s VM ориентировочно 2 vCPU и 4 ГБ RAM, control-plane лучше 6 ГБ. Это стартовая рекомендация: проверь свободную память и место под образы. Включи все три ноды и gateway-vm. Сохрани VMware snapshots всех трёх нод до изменения CNI.

Проверка на каждой ноде:

```bash
ip -br a
ip route
ping -c 2 192.168.76.254
ping -c 2 77.88.8.8
free -h
df -h /
```

Если сеть ещё не готова, сначала закончи предыдущий `service-lab`. `network/` здесь содержит справочные файлы из него; скрипты их не применяют. Не ставь нодам второй внешний интерфейс: это обход NAT-схемы задания.

Все команды `kubectl`, Helm и скрипты `00`-`08` выполняются на **k8s-cp** от обычного пользователя `worker`, которому уже настроен `~/.kube/config`. На workers нужны импорт образа и проверка CNI-файлов. `admin.conf` на workers не копируется.

## 1. Отдельный репозиторий

Создай на GitHub пустой `container-security-lab`, без автоматически добавленного README. Распакуй архив в новую папку, не поверх `service-lab`.

```bash
cd container-security-lab
git init -b master
git add .
git commit -m "Добавил лабораторию безопасности Kubernetes"
git remote add origin git@github.com:SSSimons/container-security-lab.git
git push -u origin master
```

Если имя или аккаунт другие, измени URL. Для SSH-пуша ключ должен быть добавлен в GitHub. После создания репозитория на control-plane:

```bash
git clone https://github.com/SSSimons/container-security-lab.git
cd container-security-lab
sudo apt-get update
sudo apt-get install -y curl ca-certificates tar python3 python3-venv python3-yaml
helm version
kubectl get nodes -o wide
bash scripts/00-preflight.sh
```

Нужен Helm 3.14+ или 4; kubectl уже настроен в предыдущем задании. Устанавливать Python-зависимости приложения на ноды не нужно. Если Helm ещё нет, используй [официальную инструкцию](https://helm.sh/docs/intro/install/) и скачай release archive под `linux-amd64` с проверкой SHA-256.

📸 Сними исходные Ready-ноды при желании; основные скриншоты начинаются после установки расширений.

## 2. Собери образ и импортируй на ноды

На app-vm с Docker клонируй этот же репозиторий и собери образ:

```bash
cd container-security-lab
sudo bash scripts/build-image.sh
for node in 192.168.76.20 192.168.76.21 192.168.76.22; do
  sudo scp /tmp/service-lab-security.tar worker@"$node":/tmp/
  ssh worker@"$node" 'sudo ctr -n k8s.io images import /tmp/service-lab-security.tar'
done
```

`worker` - пользователь VM из предыдущего стенда; замени, если у тебя другой. Проверить импорт на каждой ноде:

```bash
sudo ctr -n k8s.io images ls
```

Нужен образ `docker.io/library/service-lab:security-1.0.0`. `imagePullPolicy: Never` выбран специально: образ должен лежать локально на каждой ноде. Образы Cilium, Istio и Gatekeeper ноды скачивают через NAT. Не импортируй только на control-plane: приложение обычно запускается на workers.

## 3. Резервная копия и проверка CNI

На **каждой** K8s VM:

```bash
sudo mkdir -p /root/service-lab-cni-before
sudo cp -a /etc/cni/net.d/. /root/service-lab-cni-before/
sudo ls -la /etc/cni/net.d
sudo cat /etc/cni/net.d/10-flannel.conflist
ip -d link show type veth
```

В исходной цепочке ожидаются `flannel` с `hairpinMode: true`, `isDefaultGateway: true` и `portmap` с `portMappings: true`. Сравни с `deploy/platform/cni-chain.yaml`. Если файл имеет другое имя, найди актуальный `.conflist`. Если плагины или параметры отличаются, сначала перенеси реальные параметры Flannel в ConfigMap, сохранив последним `cilium-cni`; не заменяй неизвестную цепочку вслепую.

На worker должны быть veth-интерфейсы Pod: generic-veth chaining рассчитан на этот тип сети. Это схема Flannel -> portmap -> Cilium. Flannel продолжает выделять адреса и маршрутизировать, kube-proxy остаётся, masquerade Cilium выключен. Это лабораторный CNI chaining: возможности Cilium L7/IPsec в таком режиме ограничены, HTTP-политики здесь выполняет Istio.

## 4. Установи Cilium

На control-plane, из корня нового проекта:

```bash
bash scripts/01-install-cilium.sh
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

Теперь снова на каждой ноде:

```bash
sudo cat /etc/cni/net.d/05-cilium.conflist
```

Новая цепочка должна содержать `flannel`, `portmap`, `cilium-cni`. Файл `05-cilium.conflist` должен быть первым рабочим CNI-файлом по алфавиту. Наличие старого `10-flannel.conflist` допустимо: Cilium не удаляет его (`cni.exclusive: false`). Если раньше него есть другой `.conf`/`.conflist`, сначала разбери конфликт. Не удаляй конфиги наугад.

На control-plane:

```bash
bash scripts/02-recreate-baseline.sh
kubectl get ciliumendpoints -A
```

У старых Pod ещё нет Cilium endpoint, поэтому скрипт по очереди пересоздаёт CoreDNS, Traefik и приложение. У **всех** их новых Pod должны появиться endpoints с identity. Сверь имена с `kubectl get pods -A`. Если endpoints нет, не переходи к политикам: Cilium пока не управляет трафиком этих Pod.

📸 `02-cilium.jpg`: статус Cilium и endpoints приложения. Повтори снимок после финального rollout.

## 5. Установи Istio с CNI

```bash
bash scripts/03-install-istio.sh
kubectl -n istio-system get pods -o wide
```

Скрипт берёт charts из официального release archive Istio `1.31.1`, сверяет закреплённый SHA-256 и ставит base, Istio CNI, затем istiod. Это позволяет не зависеть от доступности нового Helm CDN. Архив и распакованные charts сохраняются в игнорируемой `.cache/`.

Istio CNI добавляет `istio-cni` **в существующий** `05-cilium.conflist`. Проверь на каждой ноде:

```bash
sudo cat /etc/cni/net.d/05-cilium.conflist
```

Теперь порядок: `flannel`, `portmap`, `cilium-cni`, `istio-cni`. Без этого шага sidecar может зависнуть на проверке сети. Istio CNI заменяет настройку iptables привилегированным `istio-init`: в приложении остаётся непривилегированный `istio-validation`. Platform DaemonSets Cilium и Istio CNI имеют системные привилегии в своих namespaces; ограничения приложения на них не распространяются.

Не запускай установку Cilium повторно поверх настроенного Istio без проверки итоговой цепочки: переустановка CNI может перезаписать файл. Если нужно, дождись восстановления `istio-cni` и проверь цепочку на всех нодах перед пересозданием Pod.

## 6. Установи Gatekeeper

```bash
bash scripts/04-install-gatekeeper.sh
kubectl -n gatekeeper-system get pods -o wide
kubectl get constrainttemplate servicelabsecurity
kubectl get servicelabsecurity service-lab-security -o yaml
```

Constraint действует на Pod namespace `service-lab`: обычные контейнеры, init и ephemeral. Требует безопасный UID, read-only root, запрет повышения привилегий, drop ALL, RuntimeDefault, requests/limits; запрещает hostPath, hostPort и host namespaces. UID 10001 используется для приложения, 1337 - для `istio-proxy` и `istio-validation`. Стандартные ephemeral debug-контейнеры не пройдут требование ресурсов: для диагностики предусмотрен отдельный защищённый Pod.

Webhook использует `Fail` для запросов в `service-lab`: недоступный Gatekeeper не позволяет создать там новый Pod. Контроллер в этой лаборатории имеет одну реплику; для отказоустойчивого production нужны несколько реплик и отдельный расчёт ресурсов. Gatekeeper не меняет и не удаляет старые Pod, поэтому нарушения старой версии до её rollout могут попасть в audit.

📸 `04-gatekeeper.jpg`: готовые компоненты, Constraint с `enforcementAction: deny`. После rollout проверь `status.violations`: нарушений быть не должно.

## 7. Примени ограничения и обнови приложение

```bash
bash scripts/05-deploy-security.sh
kubectl -n service-lab get pods -o wide
kubectl -n service-lab get ciliumnetworkpolicy,authorizationpolicy,sidecar,peerauthentication
```

Ожидаются две реплики приложения, каждая `2/2 Running` (app + istio-proxy), без `istio-init`. Namespace получает Istio injection и Pod Security Admission `restricted`, закреплённый под Kubernetes 1.36. Traefik остаётся вне mesh.

| Ограничение | Значение |
| --- | --- |
| app requests | CPU 100m, RAM 64Mi, ephemeral 16Mi |
| app limits | CPU 500m, RAM 256Mi, ephemeral 128Mi |
| sidecar/validation requests | CPU 50m, RAM 64Mi, ephemeral 16Mi |
| sidecar/validation limits | CPU 250m, RAM 256Mi, ephemeral 128Mi |
| Namespace requests | CPU 2, RAM 2Gi, ephemeral 1Gi |
| Namespace limits | CPU 4, RAM 4Gi, ephemeral 2Gi |
| Максимум контейнера | CPU 1, RAM 512Mi, ephemeral 512Mi |
| Pod / Service | Максимум 10 / 3 |

LimitRange заполняет отсутствующие requests/limits до Gatekeeper. Поэтому Pod без явно прописанных ресурсов может быть принят с defaults; это ожидаемое поведение, а не обход лимитов. Requests резервируют ресурс, limits задают границы; quota ограничивает сумму заявок и лимитов namespace.

UID/GID приложения - 10001, filesystem read-only. Для временных файлов выделен `/tmp` с emptyDir до 64Mi. Свои пути Envoy предоставляет injector. Корневую ФС и hostPath для приложения открыть нельзя. Seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`, capabilities `drop: ALL`. В Dockerfile у ping сняты file capabilities и setuid; безопасный sysctl `net.ipv4.ping_group_range` разрешает ICMP echo socket группе 10001, без NET_RAW.

Токен ServiceAccount не монтируется в app. Istio отдельно добавляет свой projected token с audience для получения сертификатов; это не стандартный API-токен приложения. RBAC-роли ServiceAccount приложения не выдаются.

### Какие соединения разрешены

| Направление | Разрешено |
| --- | --- |
| Traefik -> app | TCP 8000 |
| Защищённый диагностический Pod / app -> app | TCP 8000 |
| Kubelet -> sidecar probes | TCP 15020/15021 от host/remote-node |
| Pod NS -> CoreDNS | UDP/TCP 53 |
| Pod NS -> istiod | TCP 15012 |
| Pod NS -> 77.88.8.8 | Только ICMP IPv4 Echo Request, type 8 |
| Остальной ingress/egress Pod NS | Запрещён Cilium |

Cilium выбирает все Pod namespace через `endpointSelector: {}`. Стенд предполагает отсутствие других разрешающих NetworkPolicy/CiliumNetworkPolicy для этого namespace: политики складываются. Не добавляй параллельную allow-all policy. Администратор кластера и узлы остаются доверенной границей; защита от захваченного узла здесь не заявляется. Istio выбирает только app по label. Разрешены `GET /health`, `GET /metrics`, `POST /` с `Test: Hello`; остальные HTTP-запросы Envoy отклоняет с 403. Это учебная проверка заголовка, полноценную пользовательскую аутентификацию она не заменяет.

Istio ограничивает исходящий проксируемый TCP через `Sidecar` + `REGISTRY_ONLY`, оставляя сервисы своего namespace, istiod и DNS. ICMP и обход proxy ограничивает Cilium. Для Traefik без sidecar оставлен `PERMISSIVE`: входящий plain HTTP допустим, обязательный mTLS в этом варианте не заявляется. Проверки из Windows ниже проверяют существующий Ingress, не port-forward.

📸 `01-extensions.jpg`: все три расширения готовы. 📸 `06-resources.jpg`: `kubectl describe resourcequota` и `limitrange`.

## 8. Проверь HTTP через Ingress

В PowerShell Windows:

```powershell
curl.exe -i -X POST http://192.168.76.21:30080/ -H "Host: app.lab" -H "Test: Hello"
curl.exe -i -X POST http://192.168.76.21:30080/ -H "Host: app.lab"
curl.exe -i http://192.168.76.21:30080/docs -H "Host: app.lab"
curl.exe -i http://192.168.76.21:30080/health -H "Host: app.lab"
```

Результат: `200 Hello, World!`, `403 RBAC: access denied`, `403 RBAC: access denied`, `200 OK`. Если 403 возвращает приложение с текстом `Forbidden`, проверь sidecar и AuthorizationPolicy: ожидаем запрет на уровне Istio. `/health` проверяет реальный ping; если DNS-сервер перестал отвечать на ICMP, вернётся 503, а не фиктивный OK.

```bash
kubectl -n service-lab logs deployment/service-lab -c istio-proxy --tail=30
```

📸 `03-istio.jpg`: 200 и RBAC 403, рядом можно показать `2/2` и access log Envoy.

## 9. Проверь сеть, UID и файловую систему

```bash
bash scripts/06-check-runtime.sh | tee evidence/runtime.txt
```

Скрипт создаёт три диагностических Pod с локальным образом: положительный контроль во внешнем namespace, посторонний клиент и защищённый клиент в `service-lab`. Защищённый клиент без sidecar, но с ограничениями UID/ФС/ресурсов и под той же Cilium policy. Так проверяется сетевой запрет даже при обходе Envoy.

Скрипт также проверяет доступ постороннего клиента к контрольному Pod, чтобы отсутствие его сети не выдать за успешный запрет входа.

Сначала TCP к `1.1.1.1:443` должен работать у внешнего контрольного Pod. Затем тот же адрес должен быть недоступен из защищённого Pod. Если контроль не работает, результат блокировки не засчитывается: сначала проверь NAT и внешний доступ.

У защищённого Pod ping `77.88.8.8` должен работать, внутренние HTTP-запросы дают 200/403, соединение постороннего namespace с app запрещено. Проверки app показывают UID 10001, запись в `/tmp` и read-only mount с запретом записи в `/opt/service-lab`. При любом неожиданном результате скрипт завершается с ошибкой.

📸 `05-network.jpg`: положительный контроль + запрещённый TCP + разрешённый ping. 📸 `07-filesystem.jpg`: UID и два результата записи.


## 10. Проверь admission

```bash
bash scripts/07-check-admission.sh | tee evidence/admission.txt
```

Скрипт использует `kubectl create --dry-run=server`: запрещённые Pod не создаются. Ожидает конкретную причину отказа, а не любую ошибку:

| Проверка | Кто отклоняет |
| --- | --- |
| Writable root filesystem | Gatekeeper, `service-lab-security` |
| root / privileged / hostPath | PSA restricted и/или Gatekeeper |
| 8 контейнеров с limits CPU 1 | ResourceQuota: `exceeded quota` |
| Контейнер с limits CPU 2 | LimitRange: превышен maximum cpu |

Файл `checks/negative/missing-resources.yaml` оставлен для сравнения с Rego: в чистом OPA отсутствующие ресурсы запрещены, но Kubernetes LimitRange может заполнить их до проверки. Его принятие с defaults ожидаемо. Не используй его как доказательство обхода Gatekeeper.

📸 `08-admission.jpg`: отказ Gatekeeper для writable-root и отказ quota/LimitRange. Старые Pod Gatekeeper проверяет аудитом, а не удаляет. Через 30-60 секунд после rollout:

```bash
kubectl get servicelabsecurity service-lab-security -o yaml
bash scripts/08-export-evidence.sh
```

Проверь auditTimestamp и отсутствие violations. `evidence/` содержит результаты реального запуска, по умолчанию игнорируется Git. Перед публикацией проверь экспорт: не добавляй токены и полные Secrets.

## 11. Убери проверочные Pod и добавь скриншоты

```bash
kubectl -n service-lab delete pod security-probe --ignore-not-found
kubectl delete namespace security-baseline security-outsider --ignore-not-found
```

## Если что-то не запускается

```bash
kubectl -n service-lab get pods -o wide
kubectl -n service-lab describe pod <имя-pod>
kubectl -n service-lab get events --sort-by=.lastTimestamp
kubectl -n kube-system logs daemonset/cilium -c cilium-agent --tail=80
kubectl -n istio-system logs daemonset/istio-cni-node -c install-cni --tail=80
kubectl -n gatekeeper-system logs deployment/gatekeeper-controller-manager --tail=80
```

- `ErrImageNeverPull`: импортируй образ именно на ноду, где запланирован Pod.
- `istio-validation` не заканчивается: проверь четыре плагина в CNI-цепочке на этой ноде и логи Istio CNI.
- Envoy не готов: проверь endpoint istiod и разрешение TCP 15012; CoreDNS должен иметь Cilium identity.
- Traefik даёт 502/таймаут: проверь его endpoint, namespace и label `app.kubernetes.io/name=traefik`, затем app readiness.
- `/health` даёт 503: проверь NAT, ICMP type 8, ping_group_range и отсутствие capabilities у ping; не выдавай приложению NET_RAW вместо исправления.
- Admission отказал нормальному Pod: проверь UID/resources/securityContext уже после injection, сообщения Gatekeeper и namespace LimitRange.

## Источники

- [Cilium generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Cilium и Istio](https://docs.cilium.io/en/stable/network/servicemesh/istio/)
- [Istio CNI](https://istio.io/latest/docs/setup/additional-setup/cni/)
- [Istio Sidecar / REGISTRY_ONLY](https://istio.io/latest/docs/reference/config/networking/sidecar/)
- [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
