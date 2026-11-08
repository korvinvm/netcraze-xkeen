"""Команды Keenetic CLI через SSH: версия, интерфейсы, журнал."""
import re
import socket
import sys

import paramiko

SECRETS = r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md"
HOST = "192.168.2.1"
SRC = "192.168.2.145"


def creds():
    txt = open(SECRETS, encoding="utf-8").read()
    return (re.search(r"Логин:\s*`([^`]+)`", txt).group(1),
            re.search(r"Пароль:\s*`([^`]+)`", txt).group(1))


def connect():
    user, pwd = creds()
    s = socket.socket()
    s.settimeout(12)
    s.bind((SRC, 0))
    s.connect((HOST, 22))
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, 22, user, pwd, sock=s, timeout=15, look_for_keys=False, allow_agent=False)
    return c


CMDS = [
    "show version",
    "show interface",
    "show ip route",
    "show log",
]


def main():
    c = connect()
    print("ssh ok\n")
    for cmd in CMDS:
        _, out, err = c.exec_command(cmd, timeout=45)
        text = (out.read().decode("utf-8", "replace") + err.read().decode("utf-8", "replace")).strip()
        print(f"===== {cmd} =====")
        print(text[:1800] if text else "(пусто)")
        print()
    c.close()


if __name__ == "__main__":
    sys.exit(main())
