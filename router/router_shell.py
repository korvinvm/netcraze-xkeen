"""Интерактивная консоль NDMS через форвардер."""
import os
import socket
import sys
import time

import paramiko

HOST = os.getenv("ROUTER_HOST", "host.docker.internal")
PORT = int(os.getenv("ROUTER_PORT", "2222"))
USER = os.getenv("ROUTER_USER", "admin")
PASS = os.getenv("ROUTER_PASS", "")
SRC = os.getenv("ROUTER_SRC", "")


def main(lines):
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
    sh = c.invoke_shell(width=200, height=60)
    sh.settimeout(2)
    time.sleep(1)
    try:
        sh.recv(65535)
    except Exception:
        pass
    for line in lines:
        sh.send(line + "\n")
        time.sleep(1.2)
        out = b""
        try:
            while True:
                chunk = sh.recv(65535)
                if not chunk:
                    break
                out += chunk
        except Exception:
            pass
        print(f"$ {line}\n{out.decode('utf-8', 'replace').strip()}\n{'-'*40}")
    try:
        sh.send("exit\n")
        time.sleep(0.4)
    except Exception:
        pass
    c.close()


if __name__ == "__main__":
    main(sys.argv[1:])
