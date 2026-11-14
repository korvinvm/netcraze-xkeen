"""Диагностика Netcraze NC-1812 по SSH (пароль берётся из SECRETS.md, не печатается)."""
import os
import re
import sys
import socket

import paramiko

BASE = os.path.dirname(os.path.abspath(__file__))
SECRETS = os.path.join(os.path.dirname(BASE), "SECRETS.md")


def creds():
    txt = open(SECRETS, encoding="utf-8").read()
    m = re.search(r"Логин:\s*`([^`]+)`", txt)
    user = m.group(1) if m else "admin"
    # первый пароль в разделе роутера
    m = re.search(r"порт 22\s*\n-\s*Логин:\s*`[^`]+`\s*\n-\s*Пароль:\s*`([^`]+)`", txt)
    if not m:
        m = re.search(r"Пароль:\s*`([^`]+)`", txt)
    return user, m.group(1)


def connect(host="192.168.2.1", port=22):
    user, pwd = creds()
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=pwd, timeout=20,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    return c


def run(cmds, timeout=40):
    c = connect()
    for cmd in cmds:
        try:
            _, out, err = c.exec_command(cmd, timeout=timeout)
            text = out.read().decode("utf-8", "replace").strip()
            e = err.read().decode("utf-8", "replace").strip()
            print(f"$ {cmd}\n{text}")
            if e:
                print(f"  [stderr] {e}")
        except Exception as ex:
            print(f"$ {cmd}\n  ОШИБКА: {type(ex).__name__}: {ex}")
        print("-" * 50)
    c.close()


if __name__ == "__main__":
    run(sys.argv[1:] or ["uptime"])
