#!/bin/sh
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
n=0
jq -r '.outbounds[] | select((.tag // "") | startswith("proxy-")) | [.tag, (.settings.vnext[0].address // ""), ((.settings.vnext[0].port // 443) | tostring)] | @tsv' \
   $CFG/04_outbounds.json > /tmp/ob2.tsv
while IFS="$(printf '\t')" read -r tag host port; do
    [ -n "$host" ] || continue
    /opt/bin/curl -s -m 5 --connect-timeout 3 -o /dev/null "http://$host:${port:-443}" 2>/dev/null
    rc=$?
    if [ "$rc" -ne 7 ] && [ "$rc" -ne 6 ]; then
        n=$((n + 1))
    fi
done < /tmp/ob2.tsv
echo "=== живых_по_порту=$n из $(wc -l < /tmp/ob2.tsv)"
echo "--- последние записи сторожа"
grep -a "живых" /opt/var/log/xray-sub.log | tail -3
echo "--- последние записи про подписку"
grep -a "обновляю подписку" /opt/var/log/xray-sub.log | tail -3
