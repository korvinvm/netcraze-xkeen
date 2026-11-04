"""Вход ESP32 в загрузчик: пробуем обратную распиновку DTR/RTS (DTR=EN, RTS=IO0)."""
import subprocess
import sys
import time

import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM4"
cmd = sys.argv[2:] or ["flash-id"]

sp = serial.Serial(port=port, baudrate=115200, timeout=0.2)
sp.setDTR(True)   # EN low (reset)
sp.setRTS(False)  # IO0 low
time.sleep(0.15)
sp.setDTR(False)  # release reset
time.sleep(0.1)
sp.setRTS(True)   # release IO0
time.sleep(0.3)
sp.close()

pre = r"C:\Users\USER\projects\esp-tools\.venv\Scripts\python.exe"
full = [pre, "-m", "esptool", "--port", port, "--before", "no-reset", "--after", "hard-reset"] + cmd
print("run:", " ".join(full[2:]))
sys.exit(subprocess.call(full))
