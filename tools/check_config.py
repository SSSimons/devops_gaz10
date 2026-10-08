"""Проверяем структуру YAML и связи между политиками до запуска на VM."""
from pathlib import Path
import json
import yaml

root = Path(__file__).resolve().parents[1]
documents = []
for path in sorted(root.rglob("*.yaml")):
    if not any(p in path.parts for p in ("rendered", ".cache", ".venv")):
        documents.extend((path, d) for d in yaml.safe_load_all(path.read_text()) if d)
assert documents
chain = yaml.safe_load((root / "deploy/platform/cni-chain.yaml").read_text())
plugins = json.loads(chain["data"]["cni-config"])["plugins"]
assert [p["type"] for p in plugins] == ["flannel", "portmap", "cilium-cni"]
policy = yaml.safe_load((root / "deploy/policies/cilium.yaml").read_text())["spec"]
assert policy["endpointSelector"] == {}
assert not any("world" in r.get("toEntities", []) for r in policy["egress"])
icmp = [r for r in policy["egress"] if "toCIDR" in r]
assert len(icmp) == 1 and icmp[0]["toCIDR"] == ["77.88.8.8/32"]
assert icmp[0]["icmps"][0]["fields"] == [{"family": "IPv4", "type": 8}]
workload = list(yaml.safe_load_all((root / "deploy/app/workload.yaml").read_text()))
deployment = next(d for d in workload if d["kind"] == "Deployment")
probe = yaml.safe_load((root / "checks/probe.yaml").read_text())
assert probe["metadata"]["labels"]["app"] != deployment["spec"]["selector"]["matchLabels"]["app"]
assert probe["metadata"]["annotations"]["sidecar.istio.io/inject"] == "false"
assert deployment["spec"]["template"]["spec"]["containers"][0]["securityContext"]["capabilities"] == {"drop": ["ALL"]}
template = yaml.safe_load((root / "deploy/gatekeeper/template.yaml").read_text())
assert template["spec"]["targets"][0]["rego"] == (root / "policy/security.rego").read_text()
for path in root.rglob("*"):
    if path.is_file() and not any(p in path.parts for p in [".venv", "__pycache__", "rendered", ".cache"]):
        try: text = path.read_text()
        except UnicodeDecodeError: continue
        assert chr(0x2014) not in text, path
print(f"YAML и связи политик: OK ({len(documents)} документов)")
