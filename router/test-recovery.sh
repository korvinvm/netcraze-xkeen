#!/bin/sh
# Чистый перезапуск keeper и боевой тест: убиваем Xray, смотрим, кто и как быстро вернёт.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== снимаем все keeper и lock"
for p in $(ps | awk '/xray\/keeper\.sh/ && !/awk/ {print $1}'); do kill -9 "$p" 2>/dev/null; echo "kill -9 $p"; done
rm -rf /opt/var/run/keeper.lock
sleep 12
echo "=== keeper после перезапуска"
for p in $(ps | awk '/xray\/keeper\.sh/ && !/awk/ {print $1}'); do echo "pid=$p"; done

IP_BEFORE=$(/opt/bin/curl -s -m 8 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null)
TAG_BEFORE=$(cat /opt/var/xray-sub/current_tag 2>/dev/null)
echo "=== до: IP=$IP_BEFORE tag=$TAG_BEFORE"

XPID=$(pgrep -f 'xray run' | head -1)
echo "=== убиваем xray pid=$XPID"
kill -9 "$XPID" 2>/dev/null

echo "=== следим 40 с"
i=0
back=""
while [ $i -lt 20 ]; do
    sleep 2
    i=$((i + 1))
    pid=$(pgrep -f 'xray run' | head -1)
    lst=$(netstat -tuln 2>/dev/null | grep -c ':5354')
    echo "t=$((i * 2))s pid=${pid:-нет} listener=$lst"
    if [ -z "$back" ] && [ -n "$pid" ] && [ "$lst" -gt 0 ]; then back=$((i * 2)); fi
done
echo "=== слушатель вернулся на ${back:-НЕ ВЕРНУЛСЯ}с"

echo "=== туннель"
IP_AFTER=$(/opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org 2>/dev/null)
TAG_AFTER=$(cat /opt/var/xray-sub/current_tag 2>/dev/null)
echo "после: IP=$IP_AFTER tag=$TAG_AFTER"
[ "$IP_BEFORE" = "$IP_AFTER" ] && echo "сервер НЕ менялся — хорошо" || echo "сервер сменился"

echo "=== keeper за это время"
tail -n 8 /opt/var/log/xray-sub.log
echo "=== dns-watch"
tail -n 6 /opt/var/log/dns-watch.log
echo "=== fail-open: $(/opt/etc/xray/dns-failopen.sh status)"
