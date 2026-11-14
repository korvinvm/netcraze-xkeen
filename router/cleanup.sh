#!/bin/sh
# Уборка: cron-строка tick.sh (писал по строке в минуту в mark.log) и сам мусор.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== cron до"
crontab -l 2>/dev/null

TMP=/opt/var/crontab.new
crontab -l 2>/dev/null | grep -v 'tick.sh' > "$TMP"
crontab "$TMP" 2>/dev/null && echo "crontab обновлён"
rm -f "$TMP"

echo "=== cron после"
crontab -l 2>/dev/null

echo "=== размер логов"
ls -la /opt/var/log/mark.log /opt/var/log/dns-watch.log /opt/var/log/xray-sub.log 2>/dev/null
rm -f /opt/var/log/mark.log /opt/etc/xray/tick.sh
echo "mark.log и tick.sh удалены"

echo "=== место"
df -h /opt | tail -1
