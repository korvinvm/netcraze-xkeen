"""Ручной вход ESP32 в режим загрузчика через DTR/RTS, затем запуск esptool."""
import subprocess
import sys
import time

import serial

port = sys.argv[1] if len(sys.argv) > 1 else "COM4"
cmd = sys.argv[2:] or ["flash-id"]

sp = serial.Serial()
sp.port = port
sp.baudrate = 115200
sp.timeout = 0.2
sp.open()
# EN = RTS, IO0 = DTR
sp.setRTS(True)   # EN low -> reset
sp.setDTR(False)  # IO0 low
time.sleep(0.15)
sp.setRTS(False)  # release reset, IO0 still low -> download mode
time.sleep(0.1)
sp.setDTR(True)   # release IO0
time.sleep(0.3)
sp.close()

pre = r"C:\Users\USER\projects\esp-tools\.venv\Scripts\python.exe"
full = [pre, "-m", "esptool", "--port", port, "--before", "no-reset", "--after", "hard-reset"] + cmd
print("run:", " ".join(full[2:]))
sys.exit(subprocess.call(full))
