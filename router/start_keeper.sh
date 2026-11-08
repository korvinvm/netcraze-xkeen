#!/bin/sh
# Запуск сторожа так, чтобы он пережил закрытие SSH-сессии: через setsid.
PATH=/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH
export PATH
BB=/opt/bin/busybox

if $BB --list 2>/dev/null | grep -qx setsid; then
    $BB setsid /opt/etc/xray/keeper.sh >/dev/null 2>&1 &
    echo "=== started via setsid"
elif $BB --list 2>/dev/null | grep -qx nohup; then
    $BB nohup /opt/etc/xray/keeper.sh >/dev/null 2>&1 &
    echo "=== started via nohup"
else
    /opt/etc/xray/keeper.sh >/dev/null 2>&1 &
    echo "=== started plain"
fi
sleep 3
echo "=== keeper_proc=$(ps | grep '[k]eeper.sh' | grep -vc grep)"
