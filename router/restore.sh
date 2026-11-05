CFG=/opt/etc/xray/configs/05_routing.json
TAG=$(cat /opt/var/xray-sub/current_tag 2>/dev/null)
[ -n "$TAG" ] || TAG=proxy-node1-direct
jq --arg t "$TAG" '.routing.rules |= map(if ((.outboundTag // "") | startswith("proxy")) then .outboundTag=$t else . end)' /opt/var/routing.bak > $CFG
/opt/etc/init.d/S24xray restart >/dev/null 2>&1
sleep 5
echo "сервер: $TAG"
echo "IP: $(/opt/bin/curl -s -m 8 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)"
echo "gemini: $(/opt/bin/curl -s -m 8 -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:1082 https://gemini.google.com/app)"
