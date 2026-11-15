#!/bin/sh
# DNS-сторож: следит, что слушатель Xray :5354 жив и что процесс xray на месте.
# keeper.sh смотрит сквозной выход через socks и такой отказ не видит: 11.11.2026
# весь UDP из LAN отбивался, хотя туннель числился здоровым.
#
#   жив            — молчит
#   2 провала      — перезапуск /opt/etc/init.d/S24xray
#   после 2 неудач — fail-open: DNS клиентов уходит к резолверу роутера
#                    (dns-failopen.sh on), чтобы имена работали хоть как-то
#   4 перезапуска  — обновление подписки /opt/etc/xray/sub-sync.sh
#   слушатель вернулся — fail-open снимается сразу
#
# DRY=1 — только пишет в лог, ничего не перезапускает.

TICK=${TICK:-5}
LOG=/opt/var/log/dns-watch.log
PIDF=/opt/var/run/dnswatch.pid
LOCK=/opt/var/run/dnswatch.lock
FAILOPEN=/opt/etc/xray/dns-failopen.sh
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

trap '' HUP

[ -d /opt/var/log ] || mkdir -p /opt/var/log
[ -d /opt/var/run ] || mkdir -p /opt/var/run

# один экземпляр на роутер: mkdir атомарен
if ! mkdir "$LOCK" 2>/dev/null; then
    other=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
        exit 0
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
echo $$ > "$PIDF"
trap 'rm -rf "$LOCK"; rm -f "$PIDF"' EXIT INT TERM

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [dns-watch] $*" >> "$LOG"
    if [ "$(wc -l < "$LOG")" -gt 2000 ]; then
        tail -n 1500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}

listener_ok() {
    netstat -tuln 2>/dev/null | grep -q ':5354'
}

proc_ok() {
    # pgrep -f 'xray run' на этой прошивке периодически не находит живой процесс
    # (ложные «процесс xray не найден» в логе), поэтому смотрим /proc напрямую.
    # Важно: argv[0] у Xray — просто "xray", без пути, поэтому шаблон без "*/".
    for d in /proc/[0-9]*; do
        case "$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)" in
            xray\ run*|*/xray\ run*) return 0 ;;
        esac
    done
    return 1
}

fails=0
restarts=0
opened=0
log "запущен: проверка каждые ${TICK}с (слушатель :5354 + процесс xray)${DRY:+, DRY=$DRY}"

while true; do
    if listener_ok && proc_ok; then
        if [ "$fails" -gt 0 ]; then
            log "DNS снова жив (было $fails провалов подряд)"
        fi
        if [ "$opened" = "1" ]; then
            if [ "$DRY" = "1" ]; then
                log "DRY: снял бы fail-open"
            else
                [ -x "$FAILOPEN" ] && "$FAILOPEN" off
            fi
            opened=0
        fi
        fails=0
        restarts=0
    else
        fails=$((fails + 1))
        if ! proc_ok; then
            log "провал $fails: процесс xray не найден"
        else
            log "провал $fails: нет слушателя :5354"
        fi
        if [ "$fails" -ge 2 ]; then
            if [ "$DRY" = "1" ]; then
                log "DRY: перезапустил бы /opt/etc/init.d/S24xray"
            else
                log "перезапускаю Xray (/opt/etc/init.d/S24xray restart)"
                /opt/etc/init.d/S24xray restart >> "$LOG" 2>&1
            fi
            restarts=$((restarts + 1))
            fails=0
            sleep 6
            if ! listener_ok && [ "$restarts" -ge 1 ] && [ "$opened" = "0" ]; then
                if [ "$DRY" = "1" ]; then
                    log "DRY: включил бы fail-open DNS"
                else
                    log "Xray не поднимается — включаю fail-open DNS, чтобы имена работали"
                    [ -x "$FAILOPEN" ] && "$FAILOPEN" on
                fi
                opened=1
            fi
            if [ "$restarts" -ge 4 ]; then
                if [ "$DRY" = "1" ]; then
                    log "DRY: обновил бы подписку (/opt/etc/xray/sub-sync.sh)"
                else
                    log "четыре перезапуска не помогли — обновляю подписку"
                    /opt/etc/xray/sub-sync.sh >> "$LOG" 2>&1
                fi
                restarts=0
            fi
        fi
    fi
    sleep "$TICK"
done
