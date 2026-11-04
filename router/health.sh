#!/bin/sh
# Сторож туннеля: если Xray не отвечает — ищем новый сервер из подписки.
WORK="/opt/var/xray-sub"
LOG="/opt/var/log/xray-sub.log"
[ -d "$WORK" ] || mkdir -p "$WORK"
LOCK="$WORK/health.lock"
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

STAMP="$WORK/last_rotate"
COOLDOWN=900

ok=0
for i in 1 2 3 4 5; do
    ip=$(/opt/bin/curl -s -m 8 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null)
    if [ -n "$ip" ]; then ok=1; break; fi
    sleep 4
done

if [ "$ok" = "0" ]; then
    now=$(date +%s)
    prev=$(cat "$STAMP" 2>/dev/null || echo 0)
    if [ $((now - prev)) -lt $COOLDOWN ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [health] туннель молчит, но смена была недавно — ждём" >> "$LOG"
    else
        echo "$now" > "$STAMP"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [health] туннель не отвечает — ищу новый сервер" >> "$LOG"
        /opt/etc/xray/sub-sync.sh
    fi
fi
