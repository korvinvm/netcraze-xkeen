#!/bin/sh
# Сверка версий файлов и текущая схема DNS. Только чтение.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== md5 рабочих файлов"
md5sum /opt/etc/xray/sub-sync.sh /opt/etc/xray/dns-watch.sh /opt/etc/xray/keeper.sh \
       /opt/etc/xray/health.sh /opt/etc/init.d/S98dnswatch /opt/etc/init.d/S99xrayguard \
       /opt/etc/ndm/netfilter.d/zz-guest-xray.sh 2>/dev/null

echo "=== DNS-сервис на роутере"
ps | grep -E '[d]nsmasq|[n]dns' | head -5
netstat -tuln 2>/dev/null | grep ':53 ' | head -5

echo "=== show ip name-server (CLI)"
show ip name-server 2>/dev/null | head -12

echo "=== show ip dns (CLI)"
show ip dns 2>/dev/null | head -20

echo "=== какие файлы читает Xray"
ls -la /opt/etc/xray/configs/

echo "=== 07_dns.json"
cat /opt/etc/xray/configs/07_dns.json

echo "=== 03_inbounds.json: dns-in"
grep -A6 'dns-in' /opt/etc/xray/configs/03_inbounds.json | head -20

echo "=== current_tag / current"
echo "current_tag: $(cat /opt/var/xray-sub/current_tag 2>/dev/null || echo НЕТ)"
echo "current:     $(cat /opt/var/xray-sub/current 2>/dev/null || echo НЕТ)"
echo "last_rotate: $(cat /opt/var/xray-sub/last_rotate 2>/dev/null || echo НЕТ)"

echo "=== правила zz-guest-xray (полностью)"
cat /opt/etc/ndm/netfilter.d/zz-guest-xray.sh
