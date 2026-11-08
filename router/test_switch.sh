#!/bin/sh
# Проверка переключения вживую: уходим на следующий сервер и возвращаемся.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
CUR=$(jq -r '[.routing.rules[]?.outboundTag|select(.!=null and startswith("proxy"))]|.[0]' $CFG/05_routing.json)
NEXT=$(jq -r '.outbounds[]|select((.tag//"")|startswith("proxy"))|.tag' $CFG/04_outbounds.json | grep -v "^$CUR$" | head -1)
echo "=== сейчас: $CUR"
echo "=== пробуем: $NEXT"

apply() {
  jq --arg t "$1" '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy")) | .outboundTag) |= $t' \
     /opt/etc/xray/05_routing.base.json > $CFG/05_routing.json
  /opt/etc/init.d/S24xray restart >/dev/null 2>&1
  sleep 10
  /opt/bin/curl -s -m 12 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org
}

cp $CFG/05_routing.json /opt/etc/xray/05_routing.base.json
echo "=== IP на $NEXT: [$(apply $NEXT)]"
echo "=== возвращаю $CUR"
echo "=== IP на $CUR: [$(apply $CUR)]"
