#!/bin/sh
# Второй проход: почему пропадал DNS и не врёт ли сторож. Только чтение.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== память"
head -3 /proc/meminfo

echo "=== pgrep: есть ли и как отвечает"
command -v pgrep || echo "pgrep НЕТ"
i=0
while [ $i -lt 5 ]; do
    pgrep -f 'xray run' >/dev/null 2>&1
    echo "pgrep#$i rc=$? pids=$(pgrep -f 'xray run' 2>/dev/null | tr '\n' ' ')"
    i=$((i+1))
    sleep 1
done
echo "ps-счётчик: $(ps | grep -c '[x]ray')"
echo "pid из pidfile: $(cat /opt/var/run/xray.pid 2>/dev/null || echo нет)"

echo "=== сколько раз перезапускали xray (весь лог)"
grep -c 'перезапускаю Xray' /opt/var/log/dns-watch.log 2>/dev/null
echo "=== последние перезапуски"
grep 'перезапускаю Xray' /opt/var/log/dns-watch.log 2>/dev/null | tail -10

echo "=== окно 12.11 05:30-07:30 (dns-watch)"
grep -E '2026-11-12 0[5-7]:' /opt/var/log/dns-watch.log 2>/dev/null | tail -40

echo "=== окно 12.11 05:30-07:30 (xray-sub)"
grep -E '2026-11-12 0[5-7]:' /opt/var/log/xray-sub.log 2>/dev/null | tail -40

echo "=== sub-sync: кто и как часто"
grep -c 'старт обновления подписки' /opt/var/log/xray-sub.log 2>/dev/null
grep 'старт обновления подписки' /opt/var/log/xray-sub.log 2>/dev/null | tail -12

echo "=== DNS-настройки NDMS"
/opt/bin/ndmc -c 'show ip name-server' 2>/dev/null || echo "ndmc не ответил"

echo "=== системный лог NDMS (последние строки про xray/oom/dns)"
/opt/bin/ndmc -c 'show log' 2>/dev/null | tail -40

echo "=== dmesg: oom и убийства"
dmesg 2>/dev/null | grep -iE 'oom|killed process|xray' | tail -15

echo "=== init-скрипты: как запускают"
sed -n '1,40p' /opt/etc/init.d/S98dnswatch 2>/dev/null
echo "---"
grep -nE 'dns-watch|keeper|health|sub-sync' /opt/etc/init.d/S99xrayguard 2>/dev/null | head -20
