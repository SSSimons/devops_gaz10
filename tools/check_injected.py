"""Проверяем Pod после реального injector, включая init и sidecar."""
from pathlib import Path
import json
import sys
import yaml

directory = Path(sys.argv[1])
objects = list(yaml.safe_load_all((directory / "injected-workload.yaml").read_text()))
deployment = next(o for o in objects if o and o["kind"] == "Deployment")
template = deployment["spec"]["template"]
spec = template["spec"]
containers = spec["containers"] + spec.get("initContainers", [])
assert {c["name"] for c in containers} == {"app", "istio-proxy", "istio-validation"}
for container in containers:
    security = container["securityContext"]
    expected = 10001 if container["name"] == "app" else 1337
    assert security["runAsUser"] == expected
    assert security["runAsNonRoot"] is True
    assert security["readOnlyRootFilesystem"] is True
    assert security["allowPrivilegeEscalation"] is False
    assert not security.get("privileged", False)
    assert security["capabilities"] == {"drop": ["ALL"]}
    seccomp = security.get("seccompProfile", spec["securityContext"]["seccompProfile"])
    assert seccomp == {"type": "RuntimeDefault"}
    for scope in ("requests", "limits"):
        for resource in ("cpu", "memory", "ephemeral-storage"):
            assert container["resources"][scope][resource]
pod = {"apiVersion": "v1", "kind": "Pod", "metadata": template["metadata"], "spec": spec}
(directory / "injected-review.json").write_text(json.dumps({"review": {"object": pod}}))
print("Istio injection: app/sidecar/validation безопасны, privileged istio-init отсутствует")
