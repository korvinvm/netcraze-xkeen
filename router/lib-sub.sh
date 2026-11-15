#!/bin/sh
# Общие функции для sub-sync.sh, health.sh и keeper.sh.
# wan_up      — есть ли у роутера прямой выход в интернет (мимо Xray)
# wan_ip      — собственный внешний адрес (выход провайдера)
# proxy_ip    — адрес, который видит сайт при заходе через socks-вход Xray
# tunnel_ip   — адрес выхода ЧЕРЕЗ туннель; пусто, если туннель не работает
# port_open   — ответил ли TCP-порт сервера (busybox nc тут не годится)
# apply_direct — перевести клиентов на прямой выход (туннель не нужен/мёртв)
WORK="/opt/var/xray-sub"
CFG="/opt/etc/xray/configs"
LOG="/opt/var/log/xray-sub.log"
ASSET="/opt/etc/xray/dat"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$(basename "$0")] $*" >> "$LOG"; }

wan_up() {
    /opt/bin/curl --noproxy '*' -s -m 6 -o /dev/null https://1.1.1.1 2>/dev/null && return 0
    /opt/bin/curl --noproxy '*' -s -m 6 -o /dev/null https://api.ipify.org 2>/dev/null && return 0
    return 1
}

wan_ip() {
    /opt/bin/curl --noproxy '*' -s -m 8 https://api.ipify.org 2>/dev/null
}

proxy_ip() {
    /opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null
}

# Главная защита от ложного «туннель жив». При fail-open (apply_direct) правила
# маршрутизации переписаны на direct, и socks-вход честно отдаёт ISP-адрес роутера.
# Раньше такой ответ считался доказательством живого туннеля: сторож навсегда
# оставался на прямом канале и каждые 5 минут «обновлял» подписку впустую,
# хотя в свежей подписке уже лежали другие, живые серверы.
tunnel_ip() {
    ip=$(proxy_ip)
    [ -n "$ip" ] || return 1
    w=$(wan_ip)
    if [ -n "$w" ] && [ "$ip" = "$w" ]; then return 1; fi
    echo "$ip"
}

# busybox nc в этой прошивке не понимает -w (usage error, код возврата != 0),
# поэтому старый `nc -w 3 host port` объявлял мёртвыми ВСЕ живые серверы.
# curl нам нужен только ради факта TCP-соединения, сертификат не важен.
# 6 — имя не резолвится, 7 — нет соединения, 28 — таймаут; остальное = порт открыт.
port_open() {
    /opt/bin/curl --noproxy '*' -s -m 6 --connect-timeout 4 -o /dev/null "https://$1:$2/" 2>/dev/null
    case $? in
        6|7|28) return 1 ;;
    esac
    return 0
}

apply_direct() {
    [ -s "$CFG/05_routing.json" ] || return 1
    # уже на прямом выходе — не дёргаем Xray: каждый перезапуск на несколько
    # секунд убивает DNS у всех клиентов LAN (их :53 завёрнут на :5354)
    if [ -f "$WORK/fallback_direct" ] && [ -s "$WORK/05_routing.direct" ] \
       && cmp -s "$WORK/05_routing.direct" "$CFG/05_routing.json"; then
        return 0
    fi
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
