"""Проверяем политики по CRD из закреплённых релизов Cilium и Istio."""
from pathlib import Path
import sys
import yaml
from jsonschema import Draft7Validator

root = Path(__file__).resolve().parents[1]
directory = Path(sys.argv[1] if len(sys.argv) > 1 else "rendered")
schemas = {}
for name in ("cilium-crd.yaml", "istio-base.yaml"):
    for crd in yaml.safe_load_all((directory / name).read_text()):
        if not crd or crd["kind"] != "CustomResourceDefinition":
            continue
        spec = crd["spec"]
        for version in spec["versions"]:
            if version["served"]:
                key = (f'{spec["group"]}/{version["name"]}', spec["names"]["kind"])
                schemas[key] = version["schema"]["openAPIV3Schema"]

count = 0
for file in (root / "deploy/policies").glob("*.yaml"):
    for policy in yaml.safe_load_all(file.read_text()):
        validator = Draft7Validator(schemas[(policy["apiVersion"], policy["kind"])])
        errors = list(validator.iter_errors(policy))
        assert not errors, "\n".join(f"{file}: {list(e.path)}: {e.message}" for e in errors)
        count += 1
print(f"CRD: политики Cilium/Istio соответствуют схемам релизов ({count})")
