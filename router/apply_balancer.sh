#!/bin/sh
# Ставим балансировщик и перезапускаем Xray с проверкой: если туннель не поднялся,
# сами возвращаем прежний конфиг и поднимаем его.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
ASSET=/opt/etc/xray/dat
export XRAY_LOCATION_ASSET=$ASSET
X=/opt/sbin/xray
BAK=/opt/etc/xray/backup-balancer

mkdir -p "$BAK"
[ -f "$BAK/05_routing.json" ] || cp $CFG/05_routing.json "$BAK/"

jq '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy")) | .outboundTag) |= "auto"
    | .routing.balancers = [{"tag":"auto","selector":["proxy-"],"strategy":{"type":"leastPing"}}]' \
   $CFG/05_routing.json > /tmp/05.new || exit 1
cp /tmp/05.new $CFG/05_routing.json

jq -n '{observatory:{subjectSelector:["proxy-"],probeUrl:"https://www.google.com/generate_204",probeInterval:"10s",enableConcurrency:true}}' \
   > $CFG/08_observatory.json

if ! $X run -test -confdir $CFG >/tmp/xraytest.out 2>&1; then
    echo "=== TEST-FAIL"
    tail -2 /tmp/xraytest.out
    cp "$BAK/05_routing.json" $CFG/05_routing.json
    rm -f $CFG/08_observatory.json
    echo "=== откат"
    exit 1
fi
echo "=== TEST-OK, перезапускаю Xray"

/opt/etc/init.d/S24xray restart >/dev/null 2>&1
sleep 12

ip=$(/opt/bin/curl -s -m 15 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)
if [ -n "$ip" ]; then
    echo "=== РАБОТАЕТ, внешний IP=$ip"
else
    echo "=== туннель молчит — откат"
    cp "$BAK/05_routing.json" $CFG/05_routing.json
    rm -f $CFG/08_observatory.json
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1
    sleep 10
    ip2=$(/opt/bin/curl -s -m 15 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)
    echo "=== после отката IP=[$ip2]"
fi
