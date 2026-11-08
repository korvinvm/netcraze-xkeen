#!/bin/sh
echo "=== keeper_size=$(wc -c < /opt/etc/xray/keeper.sh 2>/dev/null)"
echo "=== guard_size=$(wc -c < /opt/etc/init.d/S99xrayguard 2>/dev/null)"
echo "=== init_xray=[$(ls /opt/etc/init.d/ | grep -i xray | paste -sd, -)]"
echo "=== old_running=$(ps | grep '[S]99xrayguard' | grep -vc grep)"
echo "=== keeper_running=$(ps | grep '[k]eeper.sh' | grep -vc grep)"
