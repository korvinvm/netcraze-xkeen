#!/bin/sh
# DNS fail-open для сетей, чей :53 перенаправлен в Xray (:5354).
#
# Зачем: правила lanxray/guestxray отправляют DNS клиентов на 5354. Пока Xray
# перезапускается или лежит, слушателя нет — и все клиенты остаются без имён
# (в браузере «нет интернета», хотя TCP по IP работает).
#
# Что делает: вставляет перед REDIRECT правило RETURN для dport 53, и запросы
# уходят к резолверу роутера. Как только :5354 снова слушает — правило снимается.
#
#   dns-failopen.sh on|off|status
#
# ВАЖНО: пока режим включён, DNS идёт мимо туннеля (к серверу из DHCP провайдера).
# Это осознанный размен: имена работают, но запросы видны провайдеру.

PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

MARK=/opt/var/run/dns-failopen
LOG=/opt/var/log/dns-watch.log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [dns-failopen] $*" >> "$LOG"; }

add_rule() {
    chain="$1"; proto="$2"
    iptables -t nat -C "$chain" -p "$proto" --dport 53 -j RETURN 2>/dev/null && return 0
    iptables -t nat -I "$chain" 1 -p "$proto" --dport 53 -j RETURN 2>/dev/null
}

del_rule() {
    chain="$1"; proto="$2"
    while iptables -t nat -C "$chain" -p "$proto" --dport 53 -j RETURN 2>/dev/null; do
        iptables -t nat -D "$chain" -p "$proto" --dport 53 -j RETURN 2>/dev/null || break
    done
}

has_rule() {
    iptables -t nat -C "$1" -p "$2" --dport 53 -j RETURN 2>/dev/null
}

case "${1:-status}" in
  on)
    for chain in lanxray guestxray; do
        add_rule "$chain" udp
        add_rule "$chain" tcp
    done
    echo 1 > "$MARK"
    log "включён: DNS клиентов идёт к резолверу роутера (Xray :5354 не отвечает)"
    ;;
  off)
    for chain in lanxray guestxray; do
        del_rule "$chain" udp
        del_rule "$chain" tcp
    done
    rm -f "$MARK"
    log "выключен: DNS снова через Xray :5354"
    ;;
  status)
    if has_rule lanxray udp && has_rule guestxray udp; then
        echo "включён"
    else
        echo "выключен"
    fi
    ;;
  *)
    echo "usage: $0 {on|off|status}"
    exit 2
    ;;
esac
