"""TCP-форвардер с привязкой к локальному адресу: host:2222 -> 192.168.2.1:22."""
import socket
import sys
import threading

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2222
TARGET = (sys.argv[2] if len(sys.argv) > 2 else "192.168.2.1", int(sys.argv[3]) if len(sys.argv) > 3 else 22)
SRC = sys.argv[4] if len(sys.argv) > 4 else "192.168.2.145"


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            s.close()


def handle(client):
    up = socket.socket()
    up.settimeout(10)
    try:
        up.bind((SRC, 0))
        up.connect(TARGET)
    except Exception:
        client.close()
        up.close()
        return
    up.settimeout(None)
    threading.Thread(target=pipe, args=(client, up), daemon=True).start()
    threading.Thread(target=pipe, args=(up, client), daemon=True).start()


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", PORT))
srv.listen(16)
print(f"forward 0.0.0.0:{PORT} -> {TARGET} via {SRC}", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
