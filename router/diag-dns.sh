#!/bin/sh
# Диагностика DNS/туннеля на Netcraze. Только чтение, ничего не меняет.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== время/аптайм"
date
cat /proc/uptime 2>/dev/null | cut -d' ' -f1 | sed 's/^/uptime_s: /'

echo "=== процесс xray"
ps | grep '[x]ray' | head -5

echo "=== слушатели"
netstat -tuln 2>/dev/null | grep -E ':5354|:1082|:61219|:61220' || echo "НЕТ НИ ОДНОГО"

echo "=== xray: тест конфига"
XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir /opt/etc/xray/configs 2>&1 | tail -5

echo "=== iptables: правила перехвата"
iptables -t nat -L PREROUTING -n -v 2>/dev/null | grep -E 'lanxray|guestxray' | head -10

echo "=== цепочка lanxray"
iptables -t nat -L lanxray -n -v 2>/dev/null | head -12

echo "=== выход через туннель"
/opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null || echo "socks молчит"
echo
echo "=== выход напрямую"
/opt/bin/curl -s -m 10 https://api.ipify.org 2>/dev/null || echo "direct молчит"
echo
echo "=== DNS через 5354 (изнутри роутера)"
/opt/bin/curl -s -m 6 "https://1.1.1.1/dns-query?name=ya.ru&type=A" -H 'accept: application/dns-json' 2>/dev/null | head -c 200 || echo "DoH молчит"
echo

echo "=== сторож: процессы"
ps | grep -E '[d]ns-watch|[k]eeper|[S]99xrayguard|[x]ray-guard' | head -5

echo "=== init.d"
ls /opt/etc/init.d/ 2>/dev/null | grep -iE 'xray|dns|keeper' || echo "нет"

echo "=== хвост xray-sub.log"
tail -n 25 /opt/var/log/xray-sub.log 2>/dev/null || echo "нет лога"

echo "=== хвост dns-watch.log"
tail -n 25 /opt/var/log/dns-watch.log 2>/dev/null || echo "нет лога"

echo "=== текущий сервер"
cat /opt/var/xray-sub/current 2>/dev/null || echo "нет current"
cat /opt/var/xray-sub/last_rotate 2>/dev/null | sed 's/^/last_rotate: /'

echo "=== диск /opt"
df -h /opt 2>/dev/null | tail -2
