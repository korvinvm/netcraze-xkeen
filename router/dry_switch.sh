#!/bin/sh
# Сухая проверка переключения: копируем конфиг, подставляем другой сервер,
# прогоняем xray -test. Ничего не применяем.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
T=/tmp/cfgtest
rm -rf $T; mkdir -p $T
cp $CFG/*.json $T/

cur=$(jq -r '[.routing.rules[]?.outboundTag | select(. != null and . != "direct" and . != "block")] | .[0] // empty' $T/05_routing.json)
nxt=$(jq -r '.outbounds[] | select((.tag // "") | startswith("proxy-")) | .tag' $T/04_outbounds.json | grep -v "^$cur$" | head -1)

echo "=== current=$cur"
echo "=== next=$nxt"

jq --arg t "$nxt" '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy"))) |= (.outboundTag = $t)' \
   $CFG/05_routing.json > $T/05_routing.json

echo "=== tags_after=$(jq -r '[.routing.rules[]?.outboundTag|select(.!=null)]|unique|join(",")' $T/05_routing.json)"

if XRAY_LOCATION_ASSET=$CFG/dat /opt/sbin/xray run -test -confdir $T >/tmp/xraytest.out 2>&1; then
    echo "=== TEST-OK"
else
    echo "=== TEST-FAIL"
    tail -3 /tmp/xraytest.out
fi
rm -rf $T
