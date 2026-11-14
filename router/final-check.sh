#!/bin/sh
# Финальная проверка состояния после всех правок.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== перезапуск dns-watch (подхватить новую версию)"
for p in $(ps | awk '/xray\/dns-watch\.sh/ && !/awk/ {print $1}'); do kill -9 "$p" 2>/dev/null; echo "kill -9 $p"; done
rm -rf /opt/var/run/dnswatch.lock
sleep 10

echo "=== процессы"
for p in $(ps | awk '/xray\/dns-watch\.sh|xray\/keeper\.sh/ && !/awk/ {print $1}'); do
    echo "pid=$p $(cat /proc/$p/cmdline 2>/dev/null | tr '\0' ' ')"
done
echo "xray pid=$(pgrep -f 'xray run' | head -1)"

echo "=== слушатели"
netstat -tuln 2>/dev/null | grep -E ':5354|:1082|:61219|:61220'

echo "=== туннель / прямой"
echo "через туннель: $(/opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null)"
echo "напрямую:      $(/opt/bin/curl -s -m 8 https://api.ipify.org 2>/dev/null)"

echo "=== DNS роутера"
nslookup ya.ru 192.168.2.1 2>/dev/null | grep -A2 'Name:'

echo "=== состояние сторожей"
echo "current_tag=$(cat /opt/var/xray-sub/current_tag 2>/dev/null)"
echo "current=$(cat /opt/var/xray-sub/current 2>/dev/null)"
echo "fail-open: $(/opt/etc/xray/dns-failopen.sh status)"
tail -n 3 /opt/var/log/dns-watch.log
tail -n 3 /opt/var/log/xray-sub.log

echo "=== cron"
crontab -l 2>/dev/null
