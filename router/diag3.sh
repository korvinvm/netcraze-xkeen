#!/bin/sh
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
echo "=== socks_listen=$(netstat -ltn 2>/dev/null | grep -c ':1082')"
echo "=== direct=[$(/opt/bin/curl -s -m 8 https://api.ipify.org)]"
echo "=== socks1=[$(/opt/bin/curl -s -m 12 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)]"
echo "=== socks2=[$(/opt/bin/curl -s -m 12 --socks5-hostname 127.0.0.1:1082 https://1.1.1.1/cdn-cgi/trace | grep -m1 ip=)]"
echo "=== tag=$(jq -r '[.routing.rules[]?.outboundTag|select(.!=null and startswith("proxy"))]|.[0]' $CFG/05_routing.json)"
echo "=== keeper=$(ps | grep '[k]eeper.sh' | grep -vc grep)"
echo "--- log"
tail -8 /opt/var/log/xray-sub.log
