package main

// Первичная подготовка: если Xray не установлен — скачать официальный бинарник
// под архитектуру роутера и положить в /opt/sbin. Это избавляет от ручной
// установки XKeen: остаётся только Entware.

import (
	"archive/zip"
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

func xrayAsset() (string, error) {
	switch runtime.GOARCH {
	case "arm64":
		return "Xray-linux-arm64-v8.zip", nil
	case "arm":
		return "Xray-linux-arm32-v7a.zip", nil
	case "mipsle":
		return "Xray-linux-mips32le.zip", nil
	case "amd64":
		return "Xray-linux-64.zip", nil
	}
	return "", fmt.Errorf("неизвестная архитектура %s", runtime.GOARCH)
}

func ensureXray(p paths) error {
	bin := filepath.Join(p.Root, "sbin", "xray")
	if st, err := os.Stat(bin); err == nil && st.Size() > 1<<20 {
		return nil // уже стоит — не трогаем
	}

	asset, err := xrayAsset()
	if err != nil {
		return err
	}
	urlStr := "https://github.com/XTLS/Xray-core/releases/latest/download/" + asset
	p.log("Xray не найден, скачиваю %s", asset)

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Get(urlStr)
	if err != nil {
		return fmt.Errorf("скачать Xray не вышло: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("скачать Xray не вышло: HTTP %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return err
	}

	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return err
	}

	os.MkdirAll(filepath.Join(p.Root, "sbin"), 0o755)
	os.MkdirAll(filepath.Join(p.Xray, "dat"), 0o755)

	var gotXray bool
	for _, f := range zr.File {
		name := filepath.Base(f.Name)
		switch name {
		case "xray":
			if err := extractTo(f, bin, 0o755); err != nil {
				return err
			}
			gotXray = true
		case "geoip.dat", "geosite.dat":
			extractTo(f, filepath.Join(p.Xray, "dat", name), 0o644)
			extractTo(f, filepath.Join(p.Root, "sbin", name), 0o644)
		}
	}
	if !gotXray {
		return errors.New("в архиве Xray не нашлось бинарника")
	}
	p.log("Xray установлен: %s", bin)
	return ensureInitScript(p)
}

func extractTo(f *zip.File, dst string, mode os.FileMode) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()
	tmp := dst + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, rc); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	out.Close()
	return os.Rename(tmp, dst)
}

// ensureInitScript создаёт автозапуск Xray, если его ещё нет.
func ensureInitScript(p paths) error {
	dst := filepath.Join(p.Root, "etc", "init.d", "S24xray")
	if _, err := os.Stat(dst); err == nil {
		return nil
	}
	script := `#!/bin/sh
# Автозапуск Xray (создан keen-xray)
PIDFILE="/opt/var/run/xray.pid"
LOG="/opt/var/log/xray.log"
CONF="/opt/etc/xray/configs"

start() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null && { echo "уже запущен"; return 0; }
    XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -confdir "$CONF" >>"$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1
    kill -0 "$(cat $PIDFILE)" 2>/dev/null && echo "запущен, pid $(cat $PIDFILE)" || echo "не запустился, смотри $LOG"
}

stop() {
    [ -f "$PIDFILE" ] && kill "$(cat $PIDFILE)" 2>/dev/null
    rm -f "$PIDFILE"
    echo "остановлен"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null && echo "работает" || echo "не работает" ;;
    *) echo "usage: $0 {start|stop|restart|status}" ;;
esac
`
	os.MkdirAll(filepath.Dir(dst), 0o755)
	os.MkdirAll(filepath.Join(p.Root, "var", "run"), 0o755)
	if err := os.WriteFile(dst, []byte(script), 0o755); err != nil {
		return err
	}
	p.log("создан автозапуск %s", dst)
	return nil
}
