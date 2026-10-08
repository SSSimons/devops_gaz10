"""Проверяем UID, ограничения файловой системы и ping без NET_RAW."""
import errno
import os
from pathlib import Path
import stat
import subprocess

assert os.getuid() == 10001, os.getuid()
print("UID:", os.getuid())
assert os.statvfs("/opt/service-lab").f_flag & os.ST_RDONLY, "Корневая ФС не read-only"
path = Path("/tmp/security-check")
path.write_text("ok")
path.unlink()
print("Запись в /tmp: OK")
try:
    Path("/opt/service-lab/security-check").write_text("bad")
except OSError as error:
    assert error.errno in (errno.EROFS, errno.EACCES), error
    print("Корневая ФС: read-only, запись запрещена")
else:
    raise AssertionError("Корневая ФС доступна для записи")

ping = "/usr/bin/ping"
assert not os.stat(ping).st_mode & stat.S_ISUID, "У ping остался setuid"
assert "security.capability" not in os.listxattr(ping), "У ping остались file capabilities"
subprocess.run([ping, "-c", "1", "-W", "2", "127.0.0.1"], check=True, timeout=5)
print("Непривилегированный ping: OK")
