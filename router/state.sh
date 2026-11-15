#!/bin/sh
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
. /opt/etc/xray/lib-sub.sh
echo "tunnel_ip=$(tunnel_ip) wan=$(wan_ip)"
echo "current_tag=$(cat /opt/var/xray-sub/current_tag 2>/dev/null)"
echo "tag in routing: $(jq -r '[.routing.rules[]?.outboundTag|select(.!=null and .!="direct" and .!="block")]|.[0]//empty' /opt/etc/xray/configs/05_routing.json)"
echo "fallback_direct=$(cat /opt/var/xray-sub/fallback_direct 2>/dev/null || echo нет)"
echo "alive=$(while read -r t; do h=$(jq -r --arg t "$t" '.outbounds[]|select(.tag==$t)|.settings.vnext[0].address//empty' /opt/etc/xray/configs/04_outbounds.json); p=$(jq -r --arg t "$t" '.outbounds[]|select(.tag==$t)|(.settings.vnext[0].port//443)' /opt/etc/xray/configs/04_outbounds.json); [ -n "$h" ] && port_open "$h" "$p" && echo x; done < /opt/var/xray-sub/pool.txt | wc -l)"
echo "procs:"; ps | awk '/xray\/(keeper|dns-watch)\.sh/ && !/awk/ {print "  pid="$1" "$2}'
echo "socks sites: 1.1.1.1=$(/opt/bin/curl -s -m 5 -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:1082 https://1.1.1.1) google=$(/opt/bin/curl -s -m 6 -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:1082 https://www.google.com) ya=$(/opt/bin/curl -s -m 5 -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:1082 https://ya.ru)"
echo "--- tail sub log"; tail -n 8 /opt/var/log/xray-sub.log
echo "--- tail dns-watch"; tail -n 4 /opt/var/log/dns-watch.log
