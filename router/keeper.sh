#!/bin/sh
# Круглосуточный сторож туннеля.
#
# Идея: держим наготове список серверов из уже скачанного конфига и при обрыве
# переключаемся на следующий за пару секунд — без ожидания подписки.
#
#   каждые 15 с  — проверка туннеля, при провале проверка ещё двух сайтов
#   сразу       — переключение на следующий сервер из списка (до 5 попыток)
#   список пуст — запускаем обновление подписки
#   раз в час   — плановое обновление подписки
#   раз в 5 мин — если живых серверов меньше 5, обновляем подписку
#
TICK=15
# сколько тиков живёт проход: по умолчанию бесконечно (автозапуск),
# cron может задать KEEPER_TICKS=20 и поднимать заново каждую минуту
MAX_TICKS=${KEEPER_TICKS:-100000000}
WORK="/opt/var/xray-sub"
CFG="/opt/etc/xray/configs"
POOL="$WORK/pool.txt"
ALIVE="$WORK/alive.txt"
PIDF="/opt/var/run/keeper.pid"
LOCK="/opt/var/run/keeper.lock"
# cron и автозапуск дают пустой PATH — без этого jq/curl не находятся
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
# обрыв SSH не должен убивать сторожа
trap '' HUP
. /opt/etc/xray/lib-sub.sh

[ -d "$WORK" ] || mkdir -p "$WORK"
[ -d /opt/var/run ] || mkdir -p /opt/var/run

# один сторож на роутер: лок на каталог (mkdir атомарен), второй экземпляр выходит
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

# --- что сейчас используется -------------------------------------------------
current_tag() {
    jq -r '[.routing.rules[]?.outboundTag | select(. != null and . != "direct" and . != "block")] | .[0] // empty' \
        "$CFG/05_routing.json" 2>/dev/null
}

refresh_pool() {
    jq -r '.outbounds[] | select((.tag // "") | startswith("proxy-")) | .tag' \
        "$CFG/04_outbounds.json" > "$POOL.new" 2>/dev/null
    if [ -s "$POOL.new" ]; then
        mv "$POOL.new" "$POOL"
    else
        rm -f "$POOL.new"
    fi
}

# --- проверки ----------------------------------------------------------------
probe() {
    /opt/bin/curl -s -m 5 -o /dev/null --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null && return 0
    return 1
}

probe_sites() {
    # три независимых адреса: если все молчат — это не сайт, это туннель
    n=0
    for url in https://1.1.1.1 https://ya.ru https://cloudflare.com; do
        /opt/bin/curl -s -m 4 -o /dev/null --socks5-hostname 127.0.0.1:1082 "$url" 2>/dev/null && n=$((n+1))
    done
    [ "$n" -ge 1 ]
}

# --- переключение ------------------------------------------------------------
switch_to() {
    tag="$1"
    cp "$CFG/05_routing.json" "$WORK/05_routing.prev" 2>/dev/null
    jq --arg t "$tag" '
        (.routing.rules[] | select((.outboundTag // "") | startswith("proxy"))) |= (.outboundTag = $t)
    ' "$CFG/05_routing.json" > "$WORK/05_routing.new" 2>/dev/null || return 1
    [ -s "$WORK/05_routing.new" ] || return 1
    cp "$WORK/05_routing.new" "$CFG/05_routing.json"
    if ! XRAY_LOCATION_ASSET="/opt/etc/xray/dat" /opt/sbin/xray run -test -confdir "$CFG" >/dev/null 2>&1; then
        [ -f "$WORK/05_routing.prev" ] && cp "$WORK/05_routing.prev" "$CFG/05_routing.json"
        log "конфиг с $tag не прошёл проверку — откат"
        return 1
    fi
    rm -f "$WORK/fallback_direct"
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    # Xray после перезапуска поднимается не мгновенно: даём до 15 с,
    # иначе живой сервер объявляется мёртвым и мы меняем его впустую
    i=0
    while [ "$i" -lt 5 ]; do
        sleep 3
        if probe; then
            log "переключились на $tag — туннель отвечает"
            echo "$tag" > "$WORK/current"
            echo "$tag" > "$WORK/current_tag"
            return 0
        fi
        i=$((i + 1))
    done
    log "переключились на $tag, но туннель молчит"
    return 1
}

try_servers() {
    refresh_pool
    [ -s "$POOL" ] || { log "список серверов пуст"; return 1; }
    cur=$(current_tag)
    tries=0
    while read -r tag; do
        [ -n "$tag" ] || continue
        [ "$tag" = "$cur" ] && continue
        tries=$((tries + 1))
        [ "$tries" -gt 5 ] && break
        log "пробую $tag"
        switch_to "$tag" && return 0
    done < "$POOL"
    log "перебрали 5 серверов — все молчат"
    return 1
}

# --- сколько живых серверов ---------------------------------------------------
count_alive() {
    refresh_pool
    n=0
    : > "$ALIVE"
    while read -r tag; do
        [ -n "$tag" ] || continue
        host=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | .settings.vnext[0].address // empty'             "$CFG/04_outbounds.json" 2>/dev/null)
        port=$(jq -r --arg t "$tag" '.outbounds[] | select(.tag == $t) | (.settings.vnext[0].port // 443)'             "$CFG/04_outbounds.json" 2>/dev/null)
        [ -n "$host" ] || continue
        # VLESS не отвечает по HTTP: проверяем сам порт — это быстрее и не врёт
        if nc -w 2 "$host" "${port:-443}" </dev/null >/dev/null 2>&1; then
            echo "$tag" >> "$ALIVE"
            n=$((n + 1))
        fi
    done < "$POOL"
    echo "$n"
}

# --- главный цикл -------------------------------------------------------------
log "сторож запущен: проверка каждые ${TICK}с, серверов в списке $(refresh_pool; wc -l < "$POOL" 2>/dev/null)"
# время прошлых проверок храним на диске: проход живёт 5 минут, cron поднимает новый
[ -f "$WORK/last_hour" ] || echo 0 > "$WORK/last_hour"
[ -f "$WORK/last_min5" ] || echo 0 > "$WORK/last_min5"
hour_start=$(cat "$WORK/last_hour" 2>/dev/null || echo 0)
min5_start=$(cat "$WORK/last_min5" 2>/dev/null || echo 0)
[ "$hour_start" -gt 0 ] 2>/dev/null || hour_start=$(date +%s)
[ "$min5_start" -gt 0 ] 2>/dev/null || min5_start=$(date +%s)

tick=0
fails=0
while [ $tick -lt $MAX_TICKS ]; do
    tick=$((tick + 1))
    now=$(date +%s)

    if ! probe; then
        fails=$((fails + 1))
        if probe_sites; then
            log "один сайт молчит, остальные отвечают — считаем туннель живым"
            fails=0
        elif ! wan_up; then
            log "нет интернета у самого роутера — клиенты напрямую"
            apply_direct
            fails=0
        elif [ "$fails" -lt 3 ]; then
            log "туннель не отвечает (проба $fails из 3) — ждём, сервер не меняем"
        else
            now_s=$(date +%s)
            last=$(cat "$WORK/last_switch" 2>/dev/null || echo 0)
            if [ $((now_s - last)) -lt 90 ]; then
                log "смена сервера была $((now_s - last))с назад — пауза, чтобы не гонять Xray"
            else
                echo "$now_s" > "$WORK/last_switch"
                log "три пробы подряд без ответа — переключаю сервер"
                if ! try_servers; then
                    log "свободных серверов нет — обновляю подписку"
                    /opt/etc/xray/sub-sync.sh
                fi
            fi
            fails=0
        fi
    else
        fails=0
    fi

    # раз в час — свежая подписка
    if [ $((now - hour_start)) -ge 3600 ]; then
        hour_start=$now
        echo "$now" > "$WORK/last_hour"
        log "плановое обновление подписки"
        /opt/etc/xray/sub-sync.sh
    fi

    # раз в 5 минут — если живых меньше пяти, обновляем подписку
    if [ $((now - min5_start)) -ge 300 ]; then
        min5_start=$now
        echo "$now" > "$WORK/last_min5"
        alive=$(count_alive)
        log "живых серверов: $alive"
        if [ "$alive" -lt 5 ]; then
            log "серверов мало — обновляю подписку"
            /opt/etc/xray/sub-sync.sh
        fi
    fi

    sleep $TICK
done
