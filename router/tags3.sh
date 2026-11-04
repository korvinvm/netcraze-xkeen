CFG=/opt/etc/xray/configs/05_routing.json
BAK=/opt/var/routing.bak
[ -f "$BAK" ] || cp $CFG $BAK
for tag in $(jq -r '.outbounds[].tag|select(startswith("proxy"))' /opt/etc/xray/configs/04_outbounds.json | tail -4); do
  jq --arg t "$tag" '.routing.rules |= map(if ((.outboundTag // "") | startswith("proxy")) then .outboundTag=$t else . end)' $BAK > $CFG
  /opt/etc/init.d/S24xray restart >/dev/null 2>&1
  sleep 4
  ip=$(/opt/bin/curl -s -m 8 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null)
  info=$(/opt/bin/curl -s -m 8 "http://ip-api.com/json/$ip?fields=country,city,isp,proxy,hosting" 2>/dev/null)
  code=$(/opt/bin/curl -s -m 8 -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:1082 https://gemini.google.com/app 2>/dev/null)
  echo "$tag | $ip | gemini=$code | $info"
done
