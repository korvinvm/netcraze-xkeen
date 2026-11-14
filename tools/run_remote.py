#!/usr/bin/env python3
"""Запуск shell-скрипта на роутере Netcraze.

Пароль берётся из SECRETS.md проекта, в вывод и в командную строку не попадает.
Подключение — напрямую на WAN-адрес роутера в сети 192.168.1.x (LAN 192.168.2.1
из этой подсети недоступен).

    python tools/run_remote.py router/diag-dns.sh
"""
from __future__ import annotations

import base64
import os
import re
import socket
import sys
from pathlib import Path

import paramiko

BASE = Path(__file__).resolve().parent.parent
SECRETS = BASE / "SECRETS.md"


def read_secret(key: str) -> str:
    text = SECRETS.read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"^[-\*\s]*{key}\s*:\s*(.+)$", text, re.M)
    if not m:
        return ""
    return m.group(1).strip().strip("`'\"").strip()


def main() -> int:
    if len(sys.argv) < 2:
        print("нужен путь к скрипту")
        return 2
    script = Path(sys.argv[1])
    if not script.is_absolute():
        script = BASE / script

    host = os.getenv("ROUTER_HOST", "192.168.1.65")
    port = int(os.getenv("ROUTER_PORT", "22"))
    user = os.getenv("ROUTER_USER", "admin")
    password = os.getenv("ROUTER_PASS") or read_secret("Пароль")
    src = os.getenv("ROUTER_SRC", "")

    kw = {}
    if src:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(12)
        s.bind((src, 0))
        s.connect((host, port))
        kw["sock"] = s

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=password, timeout=25,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]}, **kw)

    remote = "/opt/var/rr.sh"
    b64 = base64.b64encode(script.read_bytes()).decode()
    tmp = remote + ".b64"
    c.exec_command(f"exec rm -f {tmp}")[1].read()
    for i in range(0, len(b64), 600):
        _, o, e = c.exec_command(f'exec sh -c "printf %s \'{b64[i:i+600]}\' >> {tmp}"')
        o.read(); e.read()
    _, o, e = c.exec_command(f'exec sh -c "base64 -d {tmp} > {remote} && rm -f {tmp}"')
    o.read(); e.read()

    _, out, err = c.exec_command(f"exec sh {remote}", timeout=300)
    print(out.read().decode("utf-8", "replace").strip())
    e = err.read().decode("utf-8", "replace").strip()
    if e:
        print("STDERR:", e[:800])
    c.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
