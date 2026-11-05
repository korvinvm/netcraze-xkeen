#!/bin/sh
# Автообновление подписки для Xray на роутере Netcraze/NDMS.
#
# Устройство:
#   1. Скачиваем подписку ДВУМЯ путями: сначала напрямую, если не вышло — через
#      уже поднятый туннель (socks 127.0.0.1:1082). Так обновление проходит даже
#      когда прямой путь к подписке закрыт, а сервер ещё живой.
#   2. Проверяем, что скачалось (это правда конфиг Xray), и только потом подменяем
#      рабочие файлы. Старый конфиг не затирается до успешной проверки.
#   3. Сервера сначала щупаем TCP-коннектом (3 с), и только живые ставим в конфиг —
#      это избавляет от десятка перезапусков xray впустую.
#   4. Если ни один сервер не поднялся — откат на прежний конфиг и повтор через 10 минут.
#
# Расписание: раз в 30 минут (crontab), плюс сторож S99xrayguard проверяет связь каждую минуту.
set -u

SUB_URL_FILE="/opt/etc/xray/sub.url"
if [ -z "${SUB_URL:-}" ] && [ -f "$SUB_URL_FILE" ]; then
    SUB_URL=$(cat "$SUB_URL_FILE")
fi
if [ -z "${SUB_URL:-}" ]; then
    echo "нет адреса подписки: заполни $SUB_URL_FILE" >&2
    exit 1
fi

WORK="/opt/var/xray-sub"
CFG="/opt/etc/xray/configs"
LOG="/opt/var/log/xray-sub.log"
SOCKS="127.0.0.1:1082"
RETRY_AFTER=600   # повтор через 10 минут, если всё легло

mkdir -p "$WORK"
: >> "$LOG"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [sub-sync] $*" >> "$LOG"; }

LOCK="$WORK/sync.lock"
mkdir "$LOCK" 2>/dev/null || { log "обновление уже идёт, выходим"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "старт обновления подписки"

[ -f /opt/etc/xray/dat/geosite.dat ] || cp /opt/sbin/geosite.dat /opt/etc/xray/dat/geosite.dat 2>/dev/null
[ -f /opt/etc/xray/dat/geoip.dat ] || cp /opt/sbin/geoip.dat /opt/etc/xray/dat/geoip.dat 2>/dev/null

# ---------------------------------------------------------------- загрузка

fetch_direct() {
    curl -fsS -m 60 -A "v2rayN/6.31" "$SUB_URL" -o "$WORK/sub.new" 2>/dev/null
}

fetch_via_tunnel() {
    # туннель может быть поднят, даже если прямой путь закрыт
    curl -fsS -m 60 --socks5-hostname "$SOCKS" -A "v2rayN/6.31" "$SUB_URL" -o "$WORK/sub.new" 2>/dev/null
}

got=0
if fetch_direct; then
    log "подписка скачана напрямую"
    got=1
elif fetch_via_tunnel; then
    log "подписка скачана через туннель"
    got=1
fi

if [ "$got" -eq 0 ]; then
    log "не удалось скачать ни напрямую, ни через туннель — оставляем текущий конфиг"
    rm -f "$WORK/sub.new"
    ( sleep "$RETRY_AFTER"; /opt/etc/xray/sub-sync.sh ) >/dev/null 2>&1 &
    exit 1
fi

# ---------------------------------------------------------------- проверка

jq -e 'type=="array" and length>0 and (.[0].outbounds|length)>0' "$WORK/sub.new" >/dev/null 2>&1 \
    || { log "подписка не похожа на конфиг Xray — не трогаем рабочий"; rm -f "$WORK/sub.new"; exit 1; }

cp "$WORK/sub.new" "$WORK/sub.last" 2>/dev/null   # последняя удачная копия
mv "$WORK/sub.new" "$WORK/sub.json"

jq '{outbounds: (.[0].outbounds + [{tag:"dns-out", protocol:"dns"}])}' "$WORK/sub.json" > "$WORK/04_outbounds.new" \
    || { log "не собрались outbounds"; exit 1; }

CANDIDATES=$(jq -r '[.[0].outbounds[] | select(.tag | startswith("proxy")) | .tag] | join(" ")' "$WORK/sub.json")
[ -n "$CANDIDATES" ] || { log "в подписке нет прокси-выходов"; exit 1; }

CUR_TAG=$(cat "$WORK/current_tag" 2>/dev/null)
if [ -n "$CUR_TAG" ] && echo "$CANDIDATES" | grep -q "$CUR_TAG"; then
    CANDIDATES="$CUR_TAG $(echo "$CANDIDATES" | tr ' ' '\n' | grep -vx "$CUR_TAG" | tr '\n' ' ')"
    log "текущий сервер пробуем первым: $CUR_TAG"
fi

log "серверов в подписке: $(echo "$CANDIDATES" | wc -w)"

# ---------------------------------------------------------------- адреса для TCP-теста

host_port() {
    # $1 — тег outbound; печатает "host port"
    jq -r --arg t "$1" '.[0].outbounds[] | select(.tag==$t)
        | if .settings.vnext then (.settings.vnext[0] | "\(.address) \(.port)")
          elif .settings.servers then (.settings.servers[0] | "\(.address) \(.port)")
          else empty end' "$WORK/sub.json" 2>/dev/null
}

tcp_alive() {
    host="$1"; port="$2"
    [ -n "$host" ] && [ -n "$port" ] || return 1
    nc -w 3 "$host" "$port" </dev/null >/dev/null 2>&1
}

# ---------------------------------------------------------------- сборка и проверка

cp "$CFG/04_outbounds.json" "$WORK/04_outbounds.prev" 2>/dev/null
cp "$CFG/05_routing.json" "$WORK/05_routing.prev" 2>/dev/null

build_routing() {
    jq --arg tag "$1" '
        {
          routing: {
            domainStrategy: "IPIfNonMatch",
            domainMatcher: "hybrid",
            rules: (
              [ {type:"field", inboundTag:["dns-in"], outboundTag:"dns-out"},
                {type:"field", inboundTag:["guest","guest-all"], ip:["geoip:private"], outboundTag:"direct"},
                {type:"field", inboundTag:["guest","guest-all"], outboundTag:$tag} ]
              + [ .[0].routing.rules[]
                  | if has("balancerTag")
                    then {type:"field", inboundTag:["redirect"], outboundTag:$tag}
                    else . end ]
            )
          }
        }
    ' "$WORK/sub.json"
}

restore_prev() {
    [ -f "$WORK/04_outbounds.prev" ] && cp "$WORK/04_outbounds.prev" "$CFG/04_outbounds.json"
    [ -f "$WORK/05_routing.prev" ] && cp "$WORK/05_routing.prev" "$CFG/05_routing.json"
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
}

ok_tag=""
alive=0
for tag in $CANDIDATES; do
    hp=$(host_port "$tag")
    host=$(echo "$hp" | cut -d' ' -f1)
    port=$(echo "$hp" | cut -d' ' -f2)

    if tcp_alive "$host" "$port"; then
        alive=$((alive+1))
    else
        log "$tag: адрес не отвечает по TCP, пропускаем"
        continue
    fi

    build_routing "$tag" > "$WORK/05_routing.new" || { log "не собралось routing для $tag"; continue; }
    cp "$WORK/04_outbounds.new" "$CFG/04_outbounds.json"
    cp "$WORK/05_routing.new" "$CFG/05_routing.json"

    if ! XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir "$CFG" >/dev/null 2>&1; then
        log "$tag: конфиг не проходит проверку"
        continue
    fi

    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    sleep 4
    ip=$(/opt/bin/curl -s -m 12 --socks5-hostname "$SOCKS" https://api.ipify.org 2>/dev/null)
    if [ -n "$ip" ]; then
        ok_tag="$tag"
        log "работает через $tag, внешний IP $ip"
        break
    fi
    log "$tag: туннель не ответил"
done

if [ -z "$ok_tag" ]; then
    log "ни один сервер не поднялся (живых по TCP: $alive) — откат и повтор через ${RETRY_AFTER}с"
    restore_prev
    ( sleep "$RETRY_AFTER"; /opt/etc/xray/sub-sync.sh ) >/dev/null 2>&1 &
    exit 1
fi

echo "$ok_tag" > "$WORK/current_tag"
log "готово, активный сервер: $ok_tag"
