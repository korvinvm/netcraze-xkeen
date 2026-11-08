"""Заливка файла на роутер через CLI (exec sh -c) кусками base64."""
import base64
import re
import socket
import sys
import time

import paramiko

SECRETS = r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md"
HOST = "192.168.2.1"
SRC = "192.168.2.145"
CHUNK = 400


def creds():
    txt = open(SECRETS, encoding="utf-8").read()
    return (re.search(r"Логин:\s*`([^`]+)`", txt).group(1),
            re.search(r"Пароль:\s*`([^`]+)`", txt).group(1))


class RouterCLI:
    def __init__(self):
        u, p = creds()
        s = socket.socket()
        s.settimeout(12)
        s.bind((SRC, 0))
        s.connect((HOST, 22))
        self.c = paramiko.SSHClient()
        self.c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.c.connect(HOST, 22, u, p, sock=s, timeout=15,
                       look_for_keys=False, allow_agent=False)
        self.sh = self.c.invoke_shell(width=200, height=6000)
        time.sleep(1.2)
        self._drain()

    def _drain(self):
        while self.sh.recv_ready():
            self.sh.recv(300000)

    def run(self, cmd, wait=1.5):
        self.sh.send(cmd + "\n")
        time.sleep(wait)
        d = b""
        while self.sh.recv_ready():
            d += self.sh.recv(300000)
        t = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", d.decode("utf-8", "replace").replace("\r", ""))
        return "\n".join(l for l in t.splitlines()
                         if l.strip() and "(config)" not in l
                         and "Netcraze" not in l and "licence" not in l
                         and "netcraze.ru" not in l)

    def close(self):
        self.c.close()


def sh_c(cli, command, wait=1.5):
    return cli.run('exec sh -c "%s"' % command, wait)


def upload(cli, local, remote):
    data = open(local, "rb").read()
    b64 = base64.b64encode(data).decode()
    sh_c(cli, "rm -f /tmp/up.b64")
    for i in range(0, len(b64), CHUNK):
        part = b64[i:i + CHUNK]
        cli.run('exec sh -c "printf %%s %s >> /tmp/up.b64"' % part, wait=0.35)
    out = sh_c(cli, "base64 -d /tmp/up.b64 > %s && chmod +x %s && wc -c %s" % (remote, remote, remote), wait=3)
    return out


if __name__ == "__main__":
    local, remote = sys.argv[1], sys.argv[2]
    cli = RouterCLI()
    print(upload(cli, local, remote))
    cli.close()
