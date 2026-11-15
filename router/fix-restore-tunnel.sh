#!/bin/sh
# Возврат туннеля после залипания в fail-open + перезапуск сторожей с новым кодом.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== 1. гасим старые экземпляры сторожей (они держат старый код в памяти)"
for p in $(ps | awk '/xray\/(dns-watch|keeper)\.sh/ && !/awk/ {print $1}'); do kill -9 "$p" 2>/dev/null; echo "kill -9 $p"; done
rm -rf /opt/var/run/dnswatch.lock /opt/var/run/keeper.lock /opt/var/run/dnswatch.pid /opt/var/run/keeper.pid
sleep 2

echo "=== 2. состояние ДО"
echo "routing md5: $(md5sum /opt/etc/xray/configs/05_routing.json | cut -d' ' -f1)"
echo "fallback_direct: $(cat /opt/var/xray-sub/fallback_direct 2>/dev/null || echo нет)"
echo "socks: $(/opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org)"
echo "direct: $(/opt/bin/curl --noproxy '*' -s -m 8 https://api.ipify.org)"

echo "=== 3. полный пересбор подписки с перебором серверов"
FORCE_SYNC=1 /opt/etc/xray/sub-sync.sh
echo "sub-sync rc=$?"

echo "=== 4. состояние ПОСЛЕ"
. /opt/etc/xray/lib-sub.sh
echo "tunnel_ip: $(tunnel_ip)"
echo "wan_ip:    $(wan_ip)"
echo "current_tag: $(cat /opt/var/xray-sub/current_tag)"
echo "fallback_direct: $(cat /opt/var/xray-sub/fallback_direct 2>/dev/null || echo нет)"
echo "routing outboundTag:"; grep -o '"outboundTag": *"[^"]*"' /opt/etc/xray/configs/05_routing.json | sort | uniq -c
echo "listeners:"; netstat -tuln 2>/dev/null | grep -E ':5354|:1082|:61219'
echo "=== 5. поднимаем сторожей"
/opt/etc/init.d/S98dnswatch start 2>/dev/null || (/opt/etc/xray/dns-watch.sh </dev/null >/dev/null 2>&1 &)
/opt/etc/init.d/S99xrayguard start 2>/dev/null || (/opt/etc/xray/keeper.sh </dev/null >/dev/null 2>&1 &)
sleep 6
for p in $(ps | awk '/xray\/(dns-watch|keeper)\.sh/ && !/awk/ {print $1}'); do echo "сторож pid=$p $(tr '\0' ' ' < /proc/$p/cmdline)"; done
echo "=== 6. хвост логов"
tail -n 6 /opt/var/log/dns-watch.log
tail -n 12 /opt/var/log/xray-sub.log
