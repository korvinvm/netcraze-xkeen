#!/bin/sh
# Есть ли живой трафик клиентов через правила перехвата (счётчики растут).
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== счётчики lanxray (DNS и 80/443)"
iptables -t nat -L lanxray -n -v 2>/dev/null | head -6
echo "=== счётчики guestxray"
iptables -t nat -L guestxray -n -v 2>/dev/null | head -4
echo "=== кто в LAN (hotspot)"
show ip hotspot 2>/dev/null | grep -E '^[0-9]|address|name' | head -12
echo "=== пауза 15 с и повтор счётчиков DNS"
sleep 15
iptables -t nat -L lanxray -n -v 2>/dev/null | sed -n '3,4p'
