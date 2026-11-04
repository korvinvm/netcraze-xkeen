"""Непрерывный лог сторожа ESP32 в файл: читает COM4 и пишет строки с локальным временем."""
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM4"
OUT = r"C:\Users\USER\projects\esp-tools\wifi-watch.log"

ser = serial.Serial(PORT, 115200, timeout=1)
with open(OUT, "a", encoding="utf-8", buffering=1) as f:
    f.write(f"\n=== старт лога {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
    while True:
        try:
            raw = ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            f.write(f"{time.strftime('%H:%M:%S')} {line}\n")
            f.flush()
        except KeyboardInterrupt:
            break
        except Exception as e:
            f.write(f"{time.strftime('%H:%M:%S')} [ошибка чтения] {e}\n")
            time.sleep(2)
