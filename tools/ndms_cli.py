#!/usr/bin/env python3
"""CLI-команды NDMS на роутере (show ...) через тот же SSH.

    python tools/ndms_cli.py "show ip name-server" "show version"

В отличие от run_remote.py здесь команды идут в родной CLI NDMS, а не в shell:
через `exec sh` команды вида `show ip ...` не работают.
"""
from __future__ import annotations

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


def main() -> int:
    import os
    host = os.getenv("ROUTER_HOST", "192.168.1.65")
    port = int(os.getenv("ROUTER_PORT", "22"))
    user = os.getenv("ROUTER_USER", "admin")
    password = os.getenv("ROUTER_PASS") or read_secret("Пароль")

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=password, timeout=25,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})

    for cmd in sys.argv[1:]:
        _, out, err = c.exec_command(cmd, timeout=60)
        text = out.read().decode("utf-8", "replace").strip()
        e = err.read().decode("utf-8", "replace").strip()
        print(f"$ {cmd}\n{text}")
        if e:
            print("ERR:", e[:400])
        print("-" * 40)
    c.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
