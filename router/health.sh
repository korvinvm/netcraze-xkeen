#!/bin/sh
# Сторож туннеля. Туннель молчит -> клиенты сразу на прямой выход, поиск нового сервера.
WORK="/opt/var/xray-sub"
COOLDOWN="${COOLDOWN:-120}"

. /opt/etc/xray/lib-sub.sh

[ -d "$WORK" ] || mkdir -p "$WORK"
LOCK="$WORK/health.lock"
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

STAMP="$WORK/last_rotate"

ok=0
for i in 1 2 3; do
    ip=$(tunnel_ip)
    if [ -n "$ip" ]; then ok=1; break; fi
    sleep 4
done

if [ "$ok" = "1" ]; then
    if [ -f "$WORK/fallback_direct" ]; then
        log "туннель снова отвечает ($ip) — возвращаем обход"
        /opt/etc/xray/sub-sync.sh
    fi
    exit 0
fi

if ! wan_up; then
    log "нет WAN — туннель недоступен, клиентов оставляем напрямую"
    apply_direct
    exit 0
fi

now=$(date +%s)
prev=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ $((now - prev)) -lt "$COOLDOWN" ]; then
    log "туннель молчит, но смена была недавно — клиентов на прямой выход"
    [ -f "$WORK/fallback_direct" ] || apply_direct
else
    echo "$now" > "$STAMP"
    log "туннель не отвечает — ищу новый сервер"
    /opt/etc/xray/sub-sync.sh
fi
