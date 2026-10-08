"""Проверяем, что Helm применил настройки совместимости и безопасности."""
import json
from pathlib import Path
import sys
import yaml

directory = Path(sys.argv[1] if len(sys.argv) > 1 else "rendered")
def objects(name):
    return [d for d in yaml.safe_load_all((directory / name).read_text()) if d]
def find(items, kind, name):
    return next(d for d in items if d["kind"] == kind and d["metadata"]["name"] == name)

cilium = find(objects("cilium.yaml"), "ConfigMap", "cilium-config")["data"]
assert cilium["cni-chaining-mode"] == "generic-veth"
assert cilium["custom-cni-conf"] == "true"
assert cilium["read-cni-conf"].endswith("/cni-config")
assert cilium["write-cni-conf-when-ready"].endswith("/05-cilium.conflist")
assert cilium["kube-proxy-replacement"] == "false"
assert cilium["enable-ipv4-masquerade"] == "false"
injector = find(objects("istiod.yaml"), "ConfigMap", "istio-sidecar-injector")["data"]
values = json.loads(injector["values"])
assert values["pilot"]["cni"]["enabled"] is True, "Будет добавлен privileged istio-init"
proxy = values["global"]["proxy"]
assert proxy["seccompProfile"] == {"type": "RuntimeDefault"}
for scope in ("requests", "limits"):
    for resource in ("cpu", "memory", "ephemeral-storage"):
        assert proxy["resources"][scope][resource]
cni = find(objects("istio-cni.yaml"), "ConfigMap", "istio-cni-config")["data"]
assert cni["CNI_CONF_NAME"] == "05-cilium.conflist"
webhook = find(objects("gatekeeper.yaml"), "ValidatingWebhookConfiguration", "gatekeeper-validating-webhook-configuration")
validation = next(w for w in webhook["webhooks"] if w["name"] == "validation.gatekeeper.sh")
assert validation["failurePolicy"] == "Fail"
conditions = {
    item["name"]: item["expression"].strip()
    for item in validation.get("matchConditions", [])
}

expected_conditions = {
    "service-lab-only":
        "has(request.namespace) && request.namespace == 'service-lab'",
    "pods-only":
        "request.resource.resource == 'pods' && "
        "(!has(request.resource.group) || request.resource.group == '')",
}

assert conditions == expected_conditions, (
    f"Неверные условия webhook Gatekeeper: {conditions}"
)
print("Helm: CNI chaining, Istio CNI, proxy limits и Gatekeeper fail-closed: OK")
