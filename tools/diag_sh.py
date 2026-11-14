"""Shell на роутере через Wi-Fi: `exec sh` + подача команд в stdin."""
import re
import socket
import sys
import time
from pathlib import Path

import paramiko

SECRETS = Path(r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md")
import os
SRC = os.environ.get("SRC", "192.168.1.79")
HOST = os.environ.get("HOST", "192.168.1.65")


def creds():
    txt = SECRETS.read_text(encoding="utf-8")
    m = re.search(r"Логин:\s*`([^`]+)`\s*\n-\s*Пароль:\s*`([^`]+)`", txt)
    assert m
    return m.group(1), m.group(2)


def main(cmds):
    user, pwd = creds()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(20)
    if SRC:
        s.bind((SRC, 0))
    s.connect((HOST, 22))
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=22, username=user, password=pwd, sock=s, timeout=30,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    ch = c.get_transport().open_session()
    ch.get_pty()
    ch.exec_command("exec sh")
    time.sleep(2.0)
    if ch.recv_ready():
        ch.recv(65535)
    for cmd in cmds:
        ch.send(cmd + "\n")
        time.sleep(4.0)
        out = ""
        while ch.recv_ready():
            out += ch.recv(65535).decode("utf-8", "replace")
            time.sleep(0.2)
        out = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out).replace("\r", "")
        print("$ " + cmd)
        print(out.strip())
        print("-" * 60)
    c.close()


if __name__ == "__main__":
    main(sys.argv[1:] or ["uname -a"])
