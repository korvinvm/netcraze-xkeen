#!/bin/sh
# Автообновление подписки Liberty для Xray на роутере Netcraze/NDMS.
# Скачивает подписку, собирает конфиг, проверяет туннель и откатывает при неудаче.
set -u

# Адрес подписки в репозиторий не попадает: он равносилен паролю.
# Кладём его в /opt/etc/xray/sub.url (одна строка) или передаём через окружение.
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
REDIRECT_PORT="61219"

mkdir -p "$WORK"
: >> "$LOG"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [sub-sync] $*" >> "$LOG"; }

LOCK="$WORK/sync.lock"
mkdir "$LOCK" 2>/dev/null || { log "обновление уже идёт, выходим"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "старт обновления подписки"
[ -f /opt/etc/xray/dat/geosite.dat ] || cp /opt/sbin/geosite.dat /opt/etc/xray/dat/geosite.dat 2>/dev/null
[ -f /opt/etc/xray/dat/geoip.dat ] || cp /opt/sbin/geoip.dat /opt/etc/xray/dat/geoip.dat 2>/dev/null

curl -fsS -m 90 -A "v2rayN/6.31" "$SUB_URL" -o "$WORK/sub.new" || { log "ошибка скачивания"; exit 1; }
jq -e 'type=="array" and length>0 and (.[0].outbounds|length)>0' "$WORK/sub.new" >/dev/null 2>&1 \
    || { log "подписка не похожа на конфиг Xray"; rm -f "$WORK/sub.new"; exit 1; }
mv "$WORK/sub.new" "$WORK/sub.json"

jq '{outbounds: (.[0].outbounds + [{tag:"dns-out", protocol:"dns"}])}' "$WORK/sub.json" > "$WORK/04_outbounds.new" || { log "не собрались outbounds"; exit 1; }

CANDIDATES=$(jq -r '[.[0].outbounds[] | select(.tag | startswith("proxy")) | .tag] | join(" ")' "$WORK/sub.json")
[ -n "$CANDIDATES" ] || { log "в подписке нет прокси-выходов"; exit 1; }
# сначала пробуем сервер, который уже работает — чтобы не менять внешний IP без причины
CUR_TAG=$(cat "$WORK/current_tag" 2>/dev/null)
if [ -n "$CUR_TAG" ] && echo "$CANDIDATES" | grep -q "$CUR_TAG"; then
    CANDIDATES="$CUR_TAG $(echo "$CANDIDATES" | tr ' ' '
' | grep -vx "$CUR_TAG" | tr '
' ' ')"
    log "текущий сервер пробуем первым: $CUR_TAG"
fi

log "серверов в подписке: $(echo "$CANDIDATES" | wc -w)"

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

ok_tag=""
for tag in $CANDIDATES; do
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
    log "ни один сервер не поднялся — откат"
    [ -f "$WORK/04_outbounds.prev" ] && cp "$WORK/04_outbounds.prev" "$CFG/04_outbounds.json"
    [ -f "$WORK/05_routing.prev" ] && cp "$WORK/05_routing.prev" "$CFG/05_routing.json"
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    exit 1
fi

echo "$ok_tag" > "$WORK/current_tag"
log "готово, активный сервер: $ok_tag"
