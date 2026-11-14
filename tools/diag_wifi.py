"""SSH к роутеру через Wi-Fi-интерфейс (source binding), не трогая маршрут по умолчанию."""
import re
import socket
import sys
from pathlib import Path

import paramiko

SECRETS = Path(r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md")
SRC = "192.168.1.79"
HOST = "192.168.1.65"


def creds():
    txt = SECRETS.read_text(encoding="utf-8")
    m = re.search(r"Логин:\s*`([^`]+)`\s*\n-\s*Пароль:\s*`([^`]+)`", txt)
    return m.group(1), m.group(2)


def connect():
    user, pwd = creds()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(15)
    s.bind((SRC, 0))
    s.connect((HOST, 22))
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=22, username=user, password=pwd, sock=s, timeout=25,
              allow_agent=False, look_for_keys=False,
              disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    return c


def main(cmds):
    c = connect()
    for cmd in cmds:
        try:
            _, out, err = c.exec_command(cmd, timeout=60)
            text = out.read().decode("utf-8", "replace").strip()
            e = err.read().decode("utf-8", "replace").strip()
            print("$ " + cmd)
            print(text)
            if e:
                print("[stderr] " + e[:400])
        except Exception as ex:
            print("$ " + cmd + "\nОШИБКА: " + type(ex).__name__ + ": " + str(ex))
        print("-" * 60)
    c.close()


if __name__ == "__main__":
    main(sys.argv[1:] or ["uptime"])
