#!/bin/sh
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
h=wjivqweuhc.liberty-nodes.online
p=443
echo "=== dns: $(nslookup $h 2>&1 | tail -2 | tr '\n' ' ')"
nc -w 3 "$h" "$p" </dev/null >/dev/null 2>&1
echo "=== nc_rc=$?"
/opt/bin/curl -s -m 5 -o /dev/null --connect-timeout 4 "http://$h:$p" 2>/dev/null
echo "=== curl_rc=$?"
/opt/bin/curl -s -m 5 -o /dev/null "https://$h" 2>/dev/null
echo "=== curl_tls_rc=$?"
