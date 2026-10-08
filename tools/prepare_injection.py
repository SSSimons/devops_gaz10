"""Извлекаем конфигурацию injector из Helm для проверки без Kubernetes."""
from pathlib import Path
import sys
import yaml

directory = Path(sys.argv[1])
objects = list(yaml.safe_load_all((directory / "istiod.yaml").read_text()))
maps = {o["metadata"]["name"]: o["data"] for o in objects if o and o["kind"] == "ConfigMap"}
injector = maps["istio-sidecar-injector"]
for name, value in [("inject-config.yaml", injector["config"]),
                    ("inject-values.json", injector["values"]),
                    ("mesh.yaml", maps["istio"]["mesh"])]:
    (directory / name).write_text(value)
