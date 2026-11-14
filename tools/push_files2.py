"""Заливка файлов на роутер через Wi-Fi-канал: base64 кусками в shell."""
import base64
import re
import socket
import sys
import time
from pathlib import Path

import paramiko

SECRETS = Path(r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md")
SRC = "192.168.1.79"
HOST = "192.168.1.65"
CHUNK = 400


def creds():
    txt = SECRETS.read_text(encoding="utf-8")
    m = re.search(r"Логин:\s*`([^`]+)`\s*\n-\s*Пароль:\s*`([^`]+)`", txt)
    assert m
    return m.group(1), m.group(2)


def session():
    user, pwd = creds()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(20)
    s.bind((SRC, 0))
    s.connect((HOST, 22))
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=22, username=user, password=pwd, sock=s, timeout=30,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    ch = c.get_transport().open_session()
    ch.get_pty(width=2000)
    ch.exec_command("exec sh")
    time.sleep(2.0)
    if ch.recv_ready():
        ch.recv(65535)
    return c, ch


def run(ch, cmd, wait=1.5):
    ch.send(cmd + "\n")
    time.sleep(wait)
    out = ""
    while ch.recv_ready():
        out += ch.recv(65535).decode("utf-8", "replace")
        time.sleep(0.1)
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out).replace("\r", "")


def push(local, remote, mode="755"):
    b64 = base64.b64encode(Path(local).read_bytes()).decode()
    c, ch = session()
    try:
        tmp = "/tmp/.push.b64"
        run(ch, "rm -f " + tmp)
        first = True
        for i in range(0, len(b64), CHUNK):
            part = b64[i:i + CHUNK]
            op = ">" if first else ">>"
            first = False
            run(ch, "echo '" + part + "' " + op + " " + tmp, wait=1.5)
        print("tmp size:", run(ch, "wc -c < " + tmp).strip().splitlines()[-1:])
        run(ch, "base64 -d " + tmp + " > " + remote, wait=2.0)
        out = run(ch, "chmod " + mode + " " + remote + "; rm -f " + tmp + "; wc -c < " + remote + "; sh -n " + remote + " && echo SYNTAX_OK", wait=3.0)
        print("=== " + remote)
        print(out.strip()[-300:])
    finally:
        c.close()


if __name__ == "__main__":
    pairs = sys.argv[1:]
    for i in range(0, len(pairs), 2):
        push(pairs[i], pairs[i + 1])
