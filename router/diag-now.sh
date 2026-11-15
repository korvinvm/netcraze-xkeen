#!/bin/sh
# Read-only snapshot of the router tunnel state (no restarts, no edits).
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH

echo "=== uptime / memory"; uptime; free -m 2>/dev/null | head -3
echo "=== xray process"; for p in $(pgrep -f 'xray run'); do echo "xray pid=$p up=$(awk '{print int($1)}' /proc/$p/stat 2>/dev/null)"; done
echo "=== watchdogs"; for p in $(ps | awk '/xray\/(dns-watch|keeper)\.sh/ && !/awk/ {print $1}'); do echo "pid=$p $(tr '\0' ' ' < /proc/$p/cmdline)"; done
echo "=== listeners"; netstat -tuln 2>/dev/null | grep -E ':5354|:1082|:61219|:61220'
echo "=== tun via socks"; /opt/bin/curl -s -m 10 --socks5-hostname 127.0.0.1:1082 https://api.ipify.org; echo
echo "=== direct"; /opt/bin/curl -s -m 8 https://api.ipify.org; echo
echo "=== tcp 5354 from box"; /opt/bin/curl -s -m 3 -o /dev/null -w "5354=%{http_code}\n" http://127.0.0.1:5354/
echo "=== tag/sub state"; cat /opt/var/xray-sub/current_tag 2>/dev/null; cat /opt/var/xray-sub/current 2>/dev/null
echo "=== failopen"; /opt/etc/xray/dns-failopen.sh status 2>/dev/null
echo "=== nat lanxray"; iptables -t nat -L lanxray -n -v 2>/dev/null | head -8
echo "=== dns-watch log"; tail -n 12 /opt/var/log/dns-watch.log 2>/dev/null
echo "=== sub log"; tail -n 12 /opt/var/log/xray-sub.log 2>/dev/null
echo "=== keeper log"; tail -n 8 /opt/var/log/xray-keeper.log 2>/dev/null
echo "=== free space"; df -h /opt | tail -1
echo "=== ndms log tail"; show log 2>/dev/null | tail -25
