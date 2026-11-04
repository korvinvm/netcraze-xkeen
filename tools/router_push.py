"""Загрузка файла на роутер: содержимое уходит в stdin команды cat > путь."""
import os
import sys

import paramiko

HOST = os.getenv("ROUTER_HOST", "192.168.2.1")
USER = os.getenv("ROUTER_USER", "admin")
PASS = os.getenv("ROUTER_PASS", "")


def main(local, remote):
    data = open(local, "rb").read()
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, port=22, username=USER, password=PASS, timeout=20,
                   allow_agent=False, look_for_keys=False,
                   disabled_algorithms={"pubkeys": ["rsa-sha2-512", "rsa-sha2-256"]})
    chan = client.get_transport().open_session()
    chan.exec_command(f"exec sh -c 'cat > {remote}'")
    chan.sendall(data)
    chan.shutdown_write()
    chan.recv_exit_status()
    out = b""
    while chan.recv_ready():
        out += chan.recv(4096)
    client.close()
    print(f"загружено {len(data)} байт в {remote}")
    if out.strip():
        print(out.decode("utf-8", "replace")[:500])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
