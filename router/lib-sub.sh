�&칻!#!/bin/sh
# Общие функции для sub-sync.sh и health.sh.
# wan_up      — есть ли у роутера прямой выход в интернет (мимо Xray)
# apply_direct — перевести клиентов на прямой выход (туннель не нужен/мёртв)
WORK="/opt/var/xray-sub"
CFG="/opt/etc/xray/configs"
LOG="/opt/var/log/xray-sub.log"
ASSET="/opt/etc/xray/dat"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$(basename "$0")] $*" >> "$LOG"; }

wan_up() {
    /opt/bin/curl -s -m 6 -o /dev/null https://1.1.1.1 2>/dev/null && return 0
    /opt/bin/curl -s -m 6 -o /dev/null https://api.ipify.org 2>/dev/null && return 0
    return 1
}

tunnel_ip() {
    /opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null
}

apply_direct() {
    [ -s "$CFG/05_routing.json" ] || return 1
    jq '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy"))) |= (.outboundTag = "direct")' \
        "$CFG/05_routing.json" > "$WORK/05_routing.direct" 2>/dev/null || return 1
    jq -e '.routing.rules | length > 0' "$WORK/05_routing.direct" >/dev/null 2>&1 || return 1
    cp "$WORK/05_routing.direct" "$CFG/05_routing.json"
    if ! XRAY_LOCATION_ASSET="$ASSET" /opt/sbin/xray run -test -confdir "$CFG" >/dev/null 2>&1; then
        [ -f "$WORK/05_routing.prev" ] && cp "$WORK/05_routing.prev" "$CFG/05_routing.json"
        log "прямой выход не прошёл проверку конфига — откат"
        return 1
    fi
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    echo "$(date +%s)" > "$WORK/fallback_direct"
    log "клиенты переведены на прямой выход (без туннеля)"
    return 0
}
