#!/bin/sh
# Сколько серверов из списка реально отвечают по TCP.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
CFG=/opt/etc/xray/configs
n=0
alive=""
jq -r '.outbounds[] | select((.tag // "") | startswith("proxy-")) | [.tag, (.settings.vnext[0].address // ""), ((.settings.vnext[0].port // 443) | tostring)] | @tsv' \
   $CFG/04_outbounds.json > /tmp/ob.tsv
while IFS="$(printf '\t')" read -r tag host port; do
    [ -n "$host" ] || continue
    if nc -w 3 "$host" "$port" </dev/null >/dev/null 2>&1; then
        n=$((n + 1))
        alive="$alive $tag"
    fi
done < /tmp/ob.tsv
echo "=== живых: $n"
echo "=== список:$alive"
