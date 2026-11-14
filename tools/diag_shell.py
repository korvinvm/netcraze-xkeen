"""SSH к роутеру через Wi-Fi (интерактивный CLI): команды шлём как в терминале."""
import re
import socket
import sys
import time
from pathlib import Path

import paramiko

SECRETS = Path(r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md")
SRC = "192.168.1.79"
HOST = "192.168.1.65"


def creds():
    txt = SECRETS.read_text(encoding="utf-8")
    m = re.search(r"Логин:\s*`([^`]+)`\s*\n-\s*Пароль:\s*`([^`]+)`", txt)
    assert m
    return m.group(1), m.group(2)


def main(cmds):
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
    sh = c.invoke_shell(width=240, height=5000)
    time.sleep(2.5)
    if sh.recv_ready():
        sh.recv(65535)
    for cmd in cmds:
        sh.send(cmd + "\n")
        time.sleep(4.0)
        out = b""
        while sh.recv_ready():
            out += sh.recv(65535)
            time.sleep(0.15)
        text = out.decode("utf-8", "replace").replace("\r", "")
        text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
        print("$ " + cmd)
        print(text.strip())
        print("-" * 60)
    c.close()


if __name__ == "__main__":
    main(sys.argv[1:] or ["show version"])
