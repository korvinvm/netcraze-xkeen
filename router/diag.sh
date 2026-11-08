#!/bin/sh
# Диагностика туннеля и выхода в сеть. Печатает метки, чтобы читать без путаницы.
CURL=/opt/bin/curl
echo "=== socks_listen=$(netstat -ltn 2>/dev/null | grep -c ':1082')"
echo "=== xray_proc=$(ps | grep '[x]ray' | grep -vc grep)"
echo "=== wan_ip=[$(/sbin/ifconfig 2>/dev/null | grep -A2 'ppp' | grep 'inet addr' | head -1)]"
echo "=== direct_ip=[$($CURL -s -m 6 https://api.ipify.org)]"
echo "=== socks_ip=[$($CURL -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)]"
echo "=== socks_ya=[$($CURL -s -m 6 -o /dev/null --socks5-hostname 127.0.0.1:1082 https://ya.ru)]"
echo "=== dns_test=[$(nslookup liberty-nodes.online 2>&1 | tail -3 | tr '\n' ' ')]"
echo "=== tags=$(jq -r '[.routing.rules[]?.outboundTag|select(.!=null)]|unique|join(",")' /opt/etc/xray/configs/05_routing.json 2>&1)"
echo "=== guard_proc=$(ps | grep '[S]99xrayguard' | grep -vc grep)"
echo "=== keeper_proc=$(ps | grep '[k]eeper.sh' | grep -vc grep)"
echo "=== pool=$(grep -c 'proxy-' /opt/etc/xray/configs/04_outbounds.json 2>/dev/null)"
