"""Wi-Fi сторож для ESP32: пишет в USB-порт строки JSON о качестве связи."""
import json
import time

import network

SSID = "Netcraze-Guest"
PASS = "guest12345"
GW = "10.1.30.1"
WAN_HOST = "1.1.1.1"
WAN_PORT = 443
PERIOD = 5


def tcp_ms(host, port, timeout=3):
    s = socket_new(timeout)
    t0 = time.ticks_ms()
    try:
        s.connect((host, port))
        return time.ticks_diff(time.ticks_ms(), t0)
    except Exception:
        return -1
    finally:
        try:
            s.close()
        except Exception:
            pass


def socket_new(timeout):
    import socket

    s = socket.socket()
    s.settimeout(timeout)
    return s


def connect(wlan):
    if wlan.isconnected():
        return True
    wlan.active(False)
    time.sleep(0.3)
    wlan.active(True)
    time.sleep(0.3)
    wlan.connect(SSID, PASS)
    for _ in range(40):
        if wlan.isconnected():
            return True
        time.sleep(0.25)
    return False


def main():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    try:
        wlan.config(pm=0xA11140)  # без энергосбережения — важнее стабильность
    except Exception:
        pass

    fails = 0
    drops = 0
    was_connected = False
    last_state = None

    print("BOOT watchdog v1")
    while True:
        if not wlan.isconnected():
            code = wlan.status()
            if was_connected:
                drops += 1
                was_connected = False
                print(json.dumps({"ev": "drop", "reason": code, "drops": drops, "t": time.time()}))
            ok = connect(wlan)
            if not ok:
                fails += 1
                print(json.dumps({"ev": "reconnect_fail", "reason": wlan.status(), "fails": fails, "t": time.time()}))
                if fails >= 6:
                    print(json.dumps({"ev": "reboot"}))
                    time.sleep(1)
                    import machine

                    machine.reset()
                time.sleep(2)
                continue
            fails = 0
            print(json.dumps({"ev": "up", "ip": wlan.ifconfig()[0], "t": time.time()}))

        was_connected = True
        rssi = wlan.status("rssi")
        gw = tcp_ms(GW, 53)
        wan = tcp_ms(WAN_HOST, WAN_PORT)
        print(json.dumps({
            "ev": "sample",
            "rssi": rssi,
            "gw_ms": gw,
            "wan_ms": wan,
            "ip": wlan.ifconfig()[0],
            "drops": drops,
            "t": time.time(),
        }))
        time.sleep(PERIOD)


main()
