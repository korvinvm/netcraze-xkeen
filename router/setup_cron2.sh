#!/bin/sh
# Расписание сторожа. Пишем в оба места: системный crontab и пользовательский,
# потому что crond у разных сборок читает то одно, то другое.

cat > /opt/etc/crontab <<'EOF'
* * * * * root /opt/etc/xray/keeper.sh >/dev/null 2>&1
17 * * * * root /opt/etc/xray/sub-sync.sh >/dev/null 2>&1
EOF

mkdir -p /opt/var/spool/cron/crontabs
cat > /opt/var/spool/cron/crontabs/root <<'EOF'
* * * * * /opt/etc/xray/keeper.sh >/dev/null 2>&1
17 * * * * /opt/etc/xray/sub-sync.sh >/dev/null 2>&1
EOF
chmod 600 /opt/var/spool/cron/crontabs/root

killall crond 2>/dev/null
sleep 1
/opt/sbin/crond -L /dev/null
sleep 1

echo "=== crond: $(ps | grep '[c]rond' | grep -vc grep)"
echo "=== sys: $(wc -l < /opt/etc/crontab)"
echo "=== user: $(wc -l < /opt/var/spool/cron/crontabs/root)"
