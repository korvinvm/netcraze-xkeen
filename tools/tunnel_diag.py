"""Диагностика туннеля на роутере. Пароль читается из SECRETS.md и не печатается."""
import re
import sys

import paramiko

SECRETS = r"C:\Users\USER\projects\Netcraze_NC1812\SECRETS.md"
HOST = "192.168.2.1"


def creds():
    txt = open(SECRETS, encoding="utf-8").read()
    user = re.search(r"Логин:\s*`([^`]+)`", txt).group(1)
    pwd = re.search(r"Пароль:\s*`([^`]+)`", txt).group(1)
    return user, pwd


CMDS = [
    ("хранитель", "/opt/etc/init.d/S99xrayguard status 2>&1 | head -5"),
    ("процессы", "ps w 2>/dev/null | grep -E 'xray|Xray' | grep -v grep | head -5"),
    ("порты", "netstat -ltnp 2>/dev/null | grep -E '61219|61220|5354|1082' | head -6"),
    ("журнал", "tail -25 /opt/var/log/xray-sub.log 2>/dev/null"),
    ("WAN", "ping -c 2 -W 2 8.8.8.8 2>&1 | tail -3"),
    ("через туннель", "curl -s -m 10 -x socks5h://127.0.0.1:1082 https://ifconfig.me 2>&1 | head -2"),
    ("напрямую", "curl -s -m 8 https://ifconfig.me 2>&1 | head -2"),
    ("серверов в конфиге", "grep -c 'protocol.*vless' /opt/etc/xray/configs/*.json 2>/dev/null | head -3"),
]


def main():
    import os
    import socket

    user, pwd = creds()
    src = os.getenv("ROUTER_SRC", "192.168.2.145")
    kw = {}
    if src:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(12)
        s.bind((src, 0))
        s.connect((HOST, 22))
        kw["sock"] = s
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        c.connect(HOST, 22, user, pwd, timeout=15, look_for_keys=False, allow_agent=False, **kw)
    except Exception as e:
        print(f"НЕ ПОДКЛЮЧИЛСЯ: {type(e).__name__}: {e}")
        return 1
    print("ssh: вход выполнен\n")
    for name, cmd in CMDS:
        _, out, err = c.exec_command(cmd, timeout=40)
        text = (out.read().decode("utf-8", "replace") + err.read().decode("utf-8", "replace")).strip()
        print(f"--- {name} ---")
        print(text[:700] if text else "(пусто)")
        print()
    c.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
