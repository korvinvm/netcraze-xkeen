#!/bin/sh
# Изолируем причину: конфиг как есть, копия конфига, копия + наблюдатель, копия + балансировщик.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
X=/opt/sbin/xray
export XRAY_LOCATION_ASSET=/opt/etc/xray/dat

t() {  # $1 = папка, $2 = метка
    if $X run -test -confdir "$1" >/tmp/t.out 2>&1; then
        echo "=== $2: OK"
    else
        echo "=== $2: FAIL -> $(grep -o 'failed to[^\"]*' /tmp/t.out | tail -1)"
    fi
}

t $CFG "боевой как есть"

rm -rf /tmp/t1; mkdir -p /tmp/t1; cp $CFG/*.json /tmp/t1/
t /tmp/t1 "копия без правок"

cp $CFG/05_routing.json /tmp/t1/05_routing.json
jq '(.routing.rules[] | select((.outboundTag // "") | startswith("proxy")) | .outboundTag) |= "auto"
    | .routing.balancers = [{"tag":"auto","selector":["proxy-"],"strategy":{"type":"leastPing"}}]' \
   $CFG/05_routing.json > /tmp/t1/05_routing.json
t /tmp/t1 "копия + балансировщик"

jq -n '{observatory:{subjectSelector:["proxy-"],probeUrl:"https://www.google.com/generate_204",probeInterval:"15s",enableConcurrency:true}}' > /tmp/t1/08_observatory.json
t /tmp/t1 "копия + балансировщик + наблюдатель"
