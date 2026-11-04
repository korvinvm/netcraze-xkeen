"""SSH к роутеру через локальный форвардер (привязка к LAN-адресу ноута)."""
import os
import socket
import sys

import paramiko

HOST = os.getenv("ROUTER_HOST", "host.docker.internal")
PORT = int(os.getenv("ROUTER_PORT", "2222"))
USER = os.getenv("ROUTER_USER", "admin")
PASS = os.getenv("ROUTER_PASS", "")
SRC = os.getenv("ROUTER_SRC", "")


def connect():
    kw = {}
    if SRC:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(12)
        s.bind((SRC, 0))
        s.connect((HOST, PORT))
        kw["sock"] = s
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=PORT, username=USER, password=PASS, timeout=20,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]}, **kw)
    return c


def run(commands, timeout=60):
    c = connect()
    out = []
    for cmd in commands:
        try:
            _, stdout, stderr = c.exec_command(cmd, timeout=timeout)
            text = stdout.read().decode("utf-8", "replace").strip()
            err = stderr.read().decode("utf-8", "replace").strip()
            out.append((cmd, text + (("\nERR: " + err) if err else "")))
        except Exception as e:
            out.append((cmd, f"ОШИБКА: {type(e).__name__}: {e}"))
    c.close()
    return out


if __name__ == "__main__":
    for cmd, text in run(sys.argv[1:] or ["show system"]):
        print(f"$ {cmd}\n{text}\n" + "-" * 40)
