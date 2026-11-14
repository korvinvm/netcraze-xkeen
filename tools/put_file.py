#!/usr/bin/env python3
"""Заливка локального файла на роутер с резервной копией.

    python tools/put_file.py router/router-sub-sync.sh /opt/etc/xray/sub-sync.sh

Перед заменой существующий файл копируется в <путь>.bak-YYYYmmdd-HHMMSS,
права выставляются 0755. После заливки печатается md5 обеих сторон.
"""
from __future__ import annotations

import base64
import hashlib
import os
import re
import sys
from pathlib import Path

import paramiko

BASE = Path(__file__).resolve().parent.parent
SECRETS = BASE / "SECRETS.md"


def read_secret(key: str) -> str:
    text = SECRETS.read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"^[-\*\s]*{key}\s*:\s*(.+)$", text, re.M)
    return m.group(1).strip().strip("`'\"").strip() if m else ""


def connect():
    host = os.getenv("ROUTER_HOST", "192.168.1.65")
    port = int(os.getenv("ROUTER_PORT", "22"))
    user = os.getenv("ROUTER_USER", "admin")
    password = os.getenv("ROUTER_PASS") or read_secret("Пароль")
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=password, timeout=25,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    return c


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: put_file.py <local> <remote>")
        return 2
    local = Path(sys.argv[1])
    if not local.is_absolute():
        local = BASE / local
    remote = sys.argv[2]
    data = local.read_bytes()
    want = hashlib.md5(data).hexdigest()

    c = connect()
    tmp = "/opt/var/upload.b64"
    c.exec_command(f"exec rm -f {tmp}")[1].read()
    b64 = base64.b64encode(data).decode()
    for i in range(0, len(b64), 600):
        _, o, e = c.exec_command(f'exec sh -c "printf %s \'{b64[i:i+600]}\' >> {tmp}"')
        o.read(); e.read()
    cmd = (f'exec sh -c "base64 -d {tmp} > {remote}.new && rm -f {tmp} && '
           f'chmod 755 {remote}.new && '
           f'[ -f {remote} ] && cp {remote} {remote}.bak-$(date +%Y%m%d-%H%M%S); '
           f'mv {remote}.new {remote}; md5sum {remote}"')
    _, o, e = c.exec_command(cmd)
    out = o.read().decode("utf-8", "replace").strip()
    err = e.read().decode("utf-8", "replace").strip()
    print(out)
    if err:
        print("ERR:", err[:400])
    print("локальный md5:", want)
    ok = want in out
    print("совпало" if ok else "НЕ СОВПАЛО")
    c.close()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
