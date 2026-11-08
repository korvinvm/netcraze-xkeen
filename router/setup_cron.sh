#!/bin/sh
# Ставит расписание: сторож каждую минуту (он сам бдит по 15 секунд),
# обновление подписки раз в час. Старый health.sh больше не нужен.
cat > /opt/etc/crontab <<'EOF'
* * * * * root /opt/etc/xray/keeper.sh >/dev/null 2>&1
17 * * * * root /opt/etc/xray/sub-sync.sh >/dev/null 2>&1
EOF
killall crond 2>/dev/null
sleep 1
/opt/etc/init.d/S05crond start >/dev/null 2>&1
echo "=== crontab:"
cat /opt/etc/crontab
echo "=== crond: $(ps | grep '[c]rond' | grep -vc grep)"
