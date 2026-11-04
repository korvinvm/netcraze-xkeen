"""Заливка файла на роутер кусками base64 через форвардер."""
import base64
import hashlib
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


def main(local, remote):
    data = open(local, "rb").read()
    b64 = base64.b64encode(data).decode()
    c = connect()
    tmp = remote + ".b64"
    c.exec_command(f"exec rm -f {tmp}")[1].read()
    for i in range(0, len(b64), CHUNK):
        _, o, e = c.exec_command(f"exec sh -c \"printf %s '{b64[i:i+CHUNK]}' >> {tmp}\"")
        o.read(); e.read()
    _, o, e = c.exec_command(f"exec sh -c \"base64 -d {tmp} > {remote} && rm -f {tmp} && wc -c {remote}\"")
    print("на роутере:", o.read().decode().strip(), "| md5:", hashlib.md5(data).hexdigest())
    c.close()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
