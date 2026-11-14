#!/bin/sh
# Автообновление подписки Liberty для Xray на роутере Netcraze/NDMS.
# Логика: подписка напрямую -> нет сети, кэш -> перебор серверов (новая + старая) ->
#         всё мертво: клиентов на прямой канал, обновляем подписку напрямую и ищем в ней заново.
set -u

SUB_URL="${SUB_URL:-https://sub.conn-liberty.net/connection/subs/254305ad-65c9-4e84-b29d-66b9722e816b}"
WORK="/opt/var/xray-sub"
CFG="/opt/etc/xray/configs"
SOCKS="127.0.0.1:1082"

. /opt/etc/xray/lib-sub.sh

mkdir -p "$WORK"
: >> "$LOG"

LOCK="$WORK/sync.lock"
mkdir "$LOCK" 2>/dev/null || { log "обновление уже идёт, выходим"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

valid_sub() { jq -e 'type=="array" and length>0 and (.[0].outbounds|length)>0' "$1" >/dev/null 2>&1; }

# Подписка тянется только напрямую, мимо туннеля (--noproxy). Тоннель может быть мёртв.
fetch_sub() {
    /opt/bin/curl --noproxy '*' -fsS -m 60 -A "v2rayN/6.31" \
        -H "Cache-Control: no-cache" -H "Pragma: no-cache" "$SUB_URL" -o "$1" 2>/dev/null || return 1
    valid_sub "$1" || return 1
    return 0
}

tags_of() { jq -r '[.[0].outbounds[] | select(.tag|startswith("proxy")) | .tag] | join(" ")' "$1" 2>/dev/null; }

# host/port сервера по тегу — для TCP-проверки до перезапуска Xray
host_port() {
    jq -r --arg t "$1" '.outbounds[] | select(.tag == $t) | .settings.vnext[0]
        | "\(.address) \(.port)"' "$WORK/04_outbounds.new" 2>/dev/null
}

# ---------------------------------------------------------------- быстрый выход
# Каждый перезапуск Xray на несколько секунд убивает DNS у всех клиентов LAN:
# правила lanxray/guestxray отправляют их :53 на 5354, а слушателя нет.
# Поэтому, если туннель отвечает, подписку только сохраняем — конфиг и Xray не трогаем.
refresh_only() {
    if fetch_sub "$WORK/sub.refresh"; then
        if cmp -s "$WORK/sub.refresh" "$WORK/sub.json"; then
            log "подписка без изменений"
        else
            valid_sub "$WORK/sub.json" && cp "$WORK/sub.json" "$WORK/sub.prev.json"
            mv "$WORK/sub.refresh" "$WORK/sub.json"
            log "подписка обновлена — в работу пойдёт при следующей смене сервера"
        fi
    else
        rm -f "$WORK/sub.refresh"
        log "подписку обновить не удалось — оставляем как есть"
    fi
}

if [ -z "${FORCE_SYNC:-}" ] && [ -n "$(cat "$WORK/current_tag" 2>/dev/null)" ]; then
    if ip_a=$(tunnel_ip) && [ -n "$ip_a" ]; then
        sleep 2
        if ip_b=$(tunnel_ip) && [ -n "$ip_b" ]; then
            log "туннель жив ($ip_b), сервер $(cat "$WORK/current_tag") — Xray не перезапускаю"
            refresh_only
            exit 0
        fi
    fi
fi

log "старт обновления подписки"
[ -f /opt/etc/xray/dat/geosite.dat ] || cp /opt/sbin/geosite.dat /opt/etc/xray/dat/geosite.dat 2>/dev/null
[ -f /opt/etc/xray/dat/geoip.dat ] || cp /opt/sbin/geoip.dat /opt/etc/xray/dat/geoip.dat 2>/dev/null

# 1. свежая подписка, прямой запрос
fresh=0
if fetch_sub "$WORK/sub.new"; then
    valid_sub "$WORK/sub.json" && cp "$WORK/sub.json" "$WORK/sub.prev.json"
    mv "$WORK/sub.new" "$WORK/sub.json"
    fresh=1
    log "подписка скачана напрямую"
else
    rm -f "$WORK/sub.new"
    log "подписку скачать напрямую не удалось"
fi

# 2. нет свежей — берём кэш (без сети тоже обновляемся)
if [ "$fresh" = "0" ]; then
    if valid_sub "$WORK/sub.json"; then
        log "работаем по кэшу подписки"
    elif valid_sub "$WORK/sub.prev.json"; then
        cp "$WORK/sub.prev.json" "$WORK/sub.json"
        log "кэш битый — взяли предыдущую копию"
    else
        log "кэша нет — собирать нечего"
        exit 1
    fi
fi

jq '{outbounds: (.[0].outbounds + [{tag:"dns-out", protocol:"dns"}])}' "$WORK/sub.json" > "$WORK/04_outbounds.new" \
    || { log "не собрались outbounds"; exit 1; }

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

# сервер живой только после двух успешных ответов подряд
probe_tag() {
    i=0
    while [ "$i" -lt 2 ]; do
        ip=$(tunnel_ip)
        [ -z "$ip" ] && return 1
        i=$((i + 1))
        [ "$i" -lt 2 ] && sleep 3
    done
    return 0
}

ok_tag=""
tried=""

sweep() {
    tag="$1"
    case " $tried " in *" $tag "*) return 1 ;; esac
    tried="$tried $tag"
    # дешёвая проверка до перезапуска: мёртвый адрес не должен стоить клиентам DNS
    hp=$(host_port "$tag")
    h=$(echo "$hp" | cut -d' ' -f1)
    p=$(echo "$hp" | cut -d' ' -f2)
    if [ -n "$h" ] && [ -n "$p" ]; then
        if ! nc -w 3 "$h" "$p" </dev/null >/dev/null 2>&1; then
            log "$tag: $h:$p не отвечает по TCP — пропускаем без перезапуска Xray"
            return 1
        fi
    fi
    build_routing "$tag" > "$WORK/05_routing.new" || { log "не собралось routing для $tag"; return 1; }
    cp "$WORK/04_outbounds.new" "$CFG/04_outbounds.json"
    cp "$WORK/05_routing.new" "$CFG/05_routing.json"
    if ! XRAY_LOCATION_ASSET="$ASSET" /opt/sbin/xray run -test -confdir "$CFG" >/dev/null 2>&1; then
        log "$tag: конфиг не проходит проверку"
        return 1
    fi
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    sleep 3
    if probe_tag; then
        log "работает через $tag, внешний IP $ip"
        return 0
    fi
    log "$tag: туннель не ответил"
    return 1
}

# 3. перебор: сначала свежая подписка, потом старая — вдруг там что-то живое осталось
CAND=$(tags_of "$WORK/sub.json")
if [ -s "$WORK/sub.prev.json" ]; then
    OLD=$(tags_of "$WORK/sub.prev.json")
    [ -n "$OLD" ] && CAND="$CAND $OLD"
fi
CUR_TAG=$(cat "$WORK/current_tag" 2>/dev/null)
if [ -n "$CUR_TAG" ] && echo "$CAND" | grep -q "$CUR_TAG"; then
    CAND="$CUR_TAG $(echo "$CAND" | tr ' ' '\n' | grep -vx "$CUR_TAG" | tr '\n' ' ')"
    log "текущий сервер пробуем первым: $CUR_TAG"
fi
log "серверов к перебору: $(echo "$CAND" | tr ' ' '\n' | sort -u | grep -c .)"

if [ "${SKIP_CHECK_PROBE:-0}" != "1" ] && ! wan_up; then
    log "у роутера нет WAN — серверы проверять бессмысленно"
    apply_direct
    exit 0
fi

for tag in $CAND; do
    if sweep "$tag"; then ok_tag="$tag"; break; fi
done

# 4. всё мертво: клиентов на прямой канал и тянем подписку заново — напрямую
if [ -z "$ok_tag" ]; then
    log "все серверы мертвы — клиентов на прямой канал, обновляю подписку заново"
    apply_direct
    if fetch_sub "$WORK/sub.retry"; then
        if cmp -s "$WORK/sub.retry" "$WORK/sub.json"; then
            log "свежая подписка не изменилась — новых серверов нет"
            rm -f "$WORK/sub.retry"
        else
            cp "$WORK/sub.json" "$WORK/sub.prev.json"
            mv "$WORK/sub.retry" "$WORK/sub.json"
            jq '{outbounds: (.[0].outbounds + [{tag:"dns-out", protocol:"dns"}])}' "$WORK/sub.json" > "$WORK/04_outbounds.new"
            NEW=$(tags_of "$WORK/sub.json")
            printf '%s\n' $tried | sort -u > "$WORK/tried.txt"
            FRESH=$(printf '%s\n' $NEW | tr ' ' '\n' | grep -v -x -F -f "$WORK/tried.txt" | tr '\n' ' ')
            log "в новой подписке серверов: $(echo "$NEW" | wc -w), неопробованных: $(echo "$FRESH" | wc -w)"
            for tag in $FRESH; do
                if sweep "$tag"; then ok_tag="$tag"; break; fi
            done
        fi
    else
        rm -f "$WORK/sub.retry"
        log "повторно скачать подписку не удалось — остаёмся на прямом канале"
    fi
fi

if [ -z "$ok_tag" ]; then
    log "живого сервера нет — работаем напрямую, повтор через сторож"
    [ -f "$WORK/04_outbounds.prev" ] && cp "$WORK/04_outbounds.prev" "$CFG/04_outbounds.json"
    apply_direct
    exit 1
fi

echo "$ok_tag" > "$WORK/current_tag"
rm -f "$WORK/fallback_direct"
echo "$(date +%s)" > "$WORK/last_rotate"
log "готово, активный сервер: $ok_tag"
