"""Выполняет локальный shell-скрипт на роутере (через форвардер с привязкой к LAN)."""
import base64
import os
import socket
import sys

import paramiko

HOST = os.getenv("ROUTER_HOST", "host.docker.internal")
PORT = int(os.getenv("ROUTER_PORT", "2222"))
USER = os.getenv("ROUTER_USER", "admin")
PASS = os.getenv("ROUTER_PASS", "")
SRC = os.getenv("ROUTER_SRC", "")
CHUNK = 600


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


def main(local_script, remote="/opt/var/rr.sh"):
    data = open(local_script, "rb").read()
    c = connect()
    b64 = base64.b64encode(data).decode()
    tmp = remote + ".b64"
    c.exec_command(f"exec rm -f {tmp}")[1].read()
    for i in range(0, len(b64), CHUNK):
        _, o, e = c.exec_command(f"exec sh -c \"printf %s '{b64[i:i+CHUNK]}' >> {tmp}\"")
        o.read(); e.read()
    _, o, e = c.exec_command(f"exec sh -c \"base64 -d {tmp} > {remote} && rm -f {tmp}\"")
    o.read(); e.read()
    _, o, e = c.exec_command(f"exec sh {remote}", timeout=300)
    print(o.read().decode("utf-8", "replace").strip())
    err = e.read().decode("utf-8", "replace").strip()
    if err:
        print("STDERR:", err[:600])
    c.close()


if __name__ == "__main__":
    main(sys.argv[1], *(sys.argv[2:3] or []))
