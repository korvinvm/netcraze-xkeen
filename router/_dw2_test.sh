#!/bin/sh
# DNS-сторож: раз в 15 секунд проверяет, что Xray-слушатель :5355 жив и что
# процесс xray на месте. Разница с keeper.sh: keeper смотрит сквозной выход в
# интернет через socks, а этой проверки не хватило — 11.11.2026 весь UDP из LAN
# отбивался EHOSTUNREACH (правила lanxray/guestxray перенаправляют DNS клиентов
# на 5354), хотя сам туннель в keeper числился здоровым.
#
#   жив      — молчит
#   2 провала — перезапуск /opt/etc/init.d/S24xray
#   3 перезапуска без толку — обновление подписки /opt/etc/xray/sub-sync.sh
#
# DRY=1 — только пишет в лог, ничего не перезапускает.

TICK=${TICK:-15}
LOG=/tmp/dw2.log
PIDF=/tmp/dw2.pid
LOCK=/tmp/dw2.lock
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
    netstat -tuln 2>/dev/null | grep -q ':5355'
}

proc_ok() {
    pgrep -f 'xray run' >/dev/null 2>&1
}

fails=0
restarts=0
log "запущен: проверка каждые ${TICK}с (слушатель :5355 + процесс xray)${DRY:+, DRY=$DRY}"

while true; do
    if listener_ok && proc_ok; then
        if [ "$fails" -gt 0 ]; then
            log "DNS снова жив (было $fails провалов подряд)"
        fi
        fails=0
        restarts=0
    else
        fails=$((fails + 1))
        if ! proc_ok; then
            log "провал $fails: процесс xray не найден"
        else
            log "провал $fails: нет слушателя :5355"
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
            sleep 8
            if [ "$restarts" -ge 3 ]; then
                if [ "$DRY" = "1" ]; then
                    log "DRY: обновил бы подписку (/opt/etc/xray/sub-sync.sh)"
                else
                    log "три перезапуска не помогли — обновляю подписку"
                    /opt/etc/xray/sub-sync.sh >> "$LOG" 2>&1
                fi
                restarts=0
            fi
        fi
    fi
    sleep "$TICK"
done
