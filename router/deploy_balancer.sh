#!/bin/sh
# Включаем встроенный балансировщик Xray: он сам держит список серверов,
# раз в 10 секунд проверяет их и мгновенно уводит трафик на живой.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
BAK=/opt/etc/xray/backup-balancer-$(date +%Y%m%d-%H%M)

mkdir -p "$BAK"
cp $CFG/05_routing.json "$BAK/" 2>/dev/null

# 1. все правила, которые ходили в конкретный сервер, переводятся на балансировщик "auto"
jq '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy")) | .outboundTag) |= "auto"
    | .routing.balancers = [{"tag":"auto","selector":["proxy-"],"strategy":{"type":"leastPing"}}]' \
   "$CFG/05_routing.json" > /tmp/05.new 2>/tmp/jq.err

if [ ! -s /tmp/05.new ]; then
    echo "=== FAIL jq: $(cat /tmp/jq.err)"
    exit 1
fi
cp /tmp/05.new "$CFG/05_routing.json"

# 2. наблюдатель: опрашивает все proxy-* и сообщает балансировщику, кто жив
jq -n '{observatory:{subjectSelector:["proxy-"],probeUrl:"https://www.google.com/generate_204",probeInterval:"15s",enableConcurrency:true}}' \
   > "$CFG/08_observatory.json"

echo "=== tags: $(jq -r '[.routing.rules[]?.outboundTag|select(.!=null)]|unique|join(",")' $CFG/05_routing.json)"
echo "=== balancers: $(jq -r '.routing.balancers|length' $CFG/05_routing.json)"
echo "=== obs: $(jq -r '.observatory.probeInterval' $CFG/08_observatory.json)"

# 3. проверка конфига целиком
if XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir $CFG >/tmp/xraytest.out 2>&1; then
    echo "=== TEST-OK"
else
    echo "=== TEST-FAIL"
    tail -3 /tmp/xraytest.out
    cp "$BAK/05_routing.json" "$CFG/05_routing.json"
    rm -f "$CFG/08_observatory.json"
    echo "=== откатились"
    exit 1
fi
echo "=== backup: $BAK"
