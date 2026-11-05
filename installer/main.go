// keen-xray — установка Xray на Keenetic через XKeen без ручных правок.
//
// Один бинарник делает всё:
//   keen-xray install --sub URL          разобрать подписку, собрать конфиг, поставить сторожа
//   keen-xray sync                       обновить подписку и перебрать серверы
//   keen-xray health                     проверить туннель, при обрыве позвать sync
//   keen-xray guard                      сторож в фоне (проверка каждые 5 мин, подписка раз в 30)
//   keen-xray status                     что сейчас происходит
//   keen-xray firewall                   правила перенаправления (основная и гостевая сети)
//
// Подписки понимает любые: JSON (Liberty/v2rayN), base64-список vless/vmess/trojan и просто список ссылок.
package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ---------------------------------------------------------------- пути

type paths struct {
	Root   string // корень Entware, на роутере /opt
	Xray   string // /opt/etc/xray
	Config string // /opt/etc/xray/configs
	Work   string // /opt/var/keen-xray
	Log    string // /opt/var/log/keen-xray.log
	Bin    string // путь к самому бинарнику
}

func defaultPaths() paths {
	root := os.Getenv("KEEN_ROOT")
	if root == "" {
		root = "/opt"
	}
	bin, _ := os.Executable()
	return paths{
		Root:   root,
		Xray:   filepath.Join(root, "etc", "xray"),
		Config: filepath.Join(root, "etc", "xray", "configs"),
		Work:   filepath.Join(root, "var", "keen-xray"),
		Log:    filepath.Join(root, "var", "log", "keen-xray.log"),
		Bin:    bin,
	}
}

func (p paths) subURLFile() string { return filepath.Join(p.Xray, "sub.url") }
func (p paths) tagFile() string    { return filepath.Join(p.Work, "current_tag") }
func (p paths) subJSON() string    { return filepath.Join(p.Work, "sub.json") }
func (p paths) lastJSON() string   { return filepath.Join(p.Work, "sub.last.json") }

func (p paths) log(format string, a ...any) {
	line := fmt.Sprintf("%s [keen-xray] %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, a...))
	if f, err := os.OpenFile(p.Log, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
		f.WriteString(line)
		f.Close()
	}
	fmt.Print(line)
}

// ---------------------------------------------------------------- модели Xray

type Outbound struct {
	Tag            string         `json:"tag"`
	Protocol       string         `json:"protocol"`
	Settings       map[string]any `json:"settings,omitempty"`
	StreamSettings map[string]any `json:"streamSettings,omitempty"`
}

type subFile struct {
	Outbounds []Outbound `json:"outbounds"`
	Routing   *Routing   `json:"routing,omitempty"`
}

type Routing struct {
	DomainStrategy string `json:"domainStrategy,omitempty"`
	DomainMatcher  string `json:"domainMatcher,omitempty"`
	Rules          []Rule `json:"rules"`
}

type Rule struct {
	Type        string   `json:"type"`
	InboundTag  []string `json:"inboundTag,omitempty"`
	OutboundTag string   `json:"outboundTag,omitempty"`
	BalancerTag string   `json:"balancerTag,omitempty"`
	IP          []string `json:"ip,omitempty"`
	Domain      []string `json:"domain,omitempty"`
	Network     string   `json:"network,omitempty"`
}

// ---------------------------------------------------------------- разбор подписок

// loadSubscription забирает подписку и приводит её к списку outbound'ов.
func loadSubscription(raw []byte) ([]Outbound, *Routing, error) {
	trimmed := strings.TrimSpace(string(raw))

	// 1. Liberty и v2rayN: JSON на выходе — массив конфигов
	if strings.HasPrefix(trimmed, "[") {
		var arr []subFile
		if err := json.Unmarshal(raw, &arr); err == nil && len(arr) > 0 && len(arr[0].Outbounds) > 0 {
			return arr[0].Outbounds, arr[0].Routing, nil
		}
		// бывает один объект с массивом outbounds
		var one subFile
		if err := json.Unmarshal(raw, &one); err == nil && len(one.Outbounds) > 0 {
			return one.Outbounds, one.Routing, nil
		}
	}

	// 2. обычная подписка: base64 со ссылками
	text := trimmed
	if !strings.Contains(text, "://") {
		if dec, err := decodeBase64Loose(text); err == nil {
			text = dec
		}
	}

	var outs []Outbound
	i := 0
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		ob, err := parseURI(line)
		if err != nil {
			continue
		}
		i++
		ob.Tag = fmt.Sprintf("proxy-%d-%s", i, shortTag(ob))
		outs = append(outs, ob)
	}
	if len(outs) == 0 {
		return nil, nil, errors.New("в подписке не нашлось ни одного сервера (ожидались vless/vmess/trojan или JSON)")
	}
	return outs, nil, nil
}

func decodeBase64Loose(s string) (string, error) {
	s = strings.ReplaceAll(s, "\n", "")
	s = strings.ReplaceAll(s, "\r", "")
	s = strings.TrimSpace(s)
	if m := len(s) % 4; m != 0 {
		s += strings.Repeat("=", 4-m)
	}
	for _, enc := range []*base64.Encoding{
		base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding,
	} {
		if b, err := enc.DecodeString(s); err == nil && strings.Contains(string(b), "://") {
			return string(b), nil
		}
	}
	return "", errors.New("не base64")
}

var tagSanitizer = regexp.MustCompile(`[^a-z0-9]+`)

func shortTag(o Outbound) string {
	host := ""
	if v := o.Settings["vnext"]; v != nil {
		if arr, ok := v.([]any); ok && len(arr) > 0 {
			if m, ok := arr[0].(map[string]any); ok {
				host, _ = m["address"].(string)
			}
		}
	}
	if host == "" {
		host = "node"
	}
	host = strings.ToLower(host)
	if len(host) > 18 {
		host = host[:18]
	}
	return strings.Trim(tagSanitizer.ReplaceAllString(host, "-"), "-")
}

func parseURI(s string) (Outbound, error) {
	switch {
	case strings.HasPrefix(s, "vless://"):
		return parseVLESS(s)
	case strings.HasPrefix(s, "vmess://"):
		return parseVMess(s)
	case strings.HasPrefix(s, "trojan://"):
		return parseTrojan(s)
	}
	return Outbound{}, fmt.Errorf("неизвестная схема: %s", s[:min(12, len(s))])
}

func parseVLESS(s string) (Outbound, error) {
	u, err := url.Parse(s)
	if err != nil {
		return Outbound{}, err
	}
	host := u.Hostname()
	port, _ := strconv.Atoi(u.Port())
	if host == "" || port == 0 {
		return Outbound{}, errors.New("vless: нет адреса или порта")
	}
	q := u.Query()
	user := map[string]any{"id": u.User.Username(), "encryption": "none"}
	if flow := q.Get("flow"); flow != "" {
		user["flow"] = flow
	}

	ob := Outbound{
		Protocol: "vless",
		Settings: map[string]any{
			"vnext": []any{map[string]any{
				"address": host, "port": port, "users": []any{user},
			}},
		},
		StreamSettings: streamSettings(q, "tcp"),
	}
	return ob, nil
}

func parseTrojan(s string) (Outbound, error) {
	u, err := url.Parse(s)
	if err != nil {
		return Outbound{}, err
	}
	host := u.Hostname()
	port, _ := strconv.Atoi(u.Port())
	if host == "" || port == 0 {
		return Outbound{}, errors.New("trojan: нет адреса или порта")
	}
	ob := Outbound{
		Protocol: "trojan",
		Settings: map[string]any{
			"servers": []any{map[string]any{
				"address": host, "port": port, "password": u.User.Username(),
			}},
		},
		StreamSettings: streamSettings(u.Query(), "tcp"),
	}
	return ob, nil
}

func parseVMess(s string) (Outbound, error) {
	body := strings.TrimPrefix(s, "vmess://")
	dec, err := decodeBase64Loose(body)
	if err != nil {
		return Outbound{}, err
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(dec), &m); err != nil {
		return Outbound{}, err
	}
	host, _ := m["add"].(string)
	port := 0
	switch v := m["port"].(type) {
	case string:
		port, _ = strconv.Atoi(v)
	case float64:
		port = int(v)
	}
	if host == "" || port == 0 {
		return Outbound{}, errors.New("vmess: нет адреса или порта")
	}
	user := map[string]any{"id": m["id"], "alterId": 0, "security": "auto"}
	ob := Outbound{
		Protocol: "vmess",
		Settings: map[string]any{
			"vnext": []any{map[string]any{
				"address": host, "port": port, "users": []any{user},
			}},
		},
	}
	netw, _ := m["net"].(string)
	q := url.Values{}
	if netw != "" {
		q.Set("type", netw)
	}
	if tls, _ := m["tls"].(string); tls == "tls" {
		q.Set("security", "tls")
	}
	if sni, _ := m["sni"].(string); sni != "" {
		q.Set("sni", sni)
	}
	if p, _ := m["path"].(string); p != "" {
		q.Set("path", p)
	}
	if h, _ := m["host"].(string); h != "" {
		q.Set("host", h)
	}
	ob.StreamSettings = streamSettings(q, "tcp")
	return ob, nil
}

func streamSettings(q url.Values, defNet string) map[string]any {
	netw := q.Get("type")
	if netw == "" {
		netw = defNet
	}
	sec := q.Get("security")
	if sec == "" {
		sec = "none"
	}

	ss := map[string]any{"network": netw, "security": sec}

	switch netw {
	case "ws":
		ws := map[string]any{"path": "/"}
		if p := q.Get("path"); p != "" {
			ws["path"] = p
		}
		if h := q.Get("host"); h != "" {
			ws["headers"] = map[string]any{"Host": h}
		}
		ss["wsSettings"] = ws
	case "grpc":
		name := q.Get("serviceName")
		if name == "" {
			name = q.Get("path")
		}
		ss["grpcSettings"] = map[string]any{"serviceName": name}
	case "tcp":
		ss["tcpSettings"] = map[string]any{"header": map[string]any{"type": "none"}}
	}

	switch sec {
	case "tls":
		tls := map[string]any{
			"serverName": firstNonEmpty(q.Get("sni"), q.Get("host")),
			"allowInsecure": false,
		}
		if fp := q.Get("fp"); fp != "" {
			tls["fingerprint"] = fp
		}
		ss["tlsSettings"] = tls
	case "reality":
		reality := map[string]any{
			"serverName":  q.Get("sni"),
			"fingerprint": firstNonEmpty(q.Get("fp"), "chrome"),
			"publicKey":   q.Get("pbk"),
			"shortId":     q.Get("sid"),
			"spiderX":     firstNonEmpty(q.Get("spx"), "/"),
		}
		ss["realitySettings"] = reality
	}
	return ss
}

func firstNonEmpty(v ...string) string {
	for _, s := range v {
		if s != "" {
			return s
		}
	}
	return ""
}

// ---------------------------------------------------------------- сборка конфига

func buildConfig(outs []Outbound, route string) ([]byte, []byte, error) {
	// outbounds: подписка + служебные
	var all []any
	for _, o := range outs {
		all = append(all, o)
	}
	all = append(all,
		map[string]any{"tag": "direct", "protocol": "freedom"},
		map[string]any{"tag": "block", "protocol": "blackhole"},
		map[string]any{"tag": "dns-out", "protocol": "dns"},
	)
	outJSON, err := json.MarshalIndent(map[string]any{"outbounds": all}, "", "  ")
	if err != nil {
		return nil, nil, err
	}

	rules := []Rule{
		{Type: "field", InboundTag: []string{"dns-in"}, OutboundTag: "dns-out"},
		{Type: "field", InboundTag: []string{"guest"}, IP: []string{"geoip:private"}, OutboundTag: "direct"},
	}
	if route == "ru-direct" {
		rules = append(rules,
			Rule{Type: "field", Domain: []string{"geosite:category-ru", "geosite:private"}, OutboundTag: "direct"},
			Rule{Type: "field", IP: []string{"geoip:ru"}, OutboundTag: "direct"},
		)
	}
	routing := Routing{
		DomainStrategy: "IPIfNonMatch",
		DomainMatcher:  "hybrid",
		Rules:          rules,
	}
	// первый сервер считаем основным; остальные остаются в конфиге как запас
	mainTag := outs[0].Tag
	routing.Rules = append(routing.Rules,
		Rule{Type: "field", InboundTag: []string{"guest"}, OutboundTag: mainTag},
		Rule{Type: "field", InboundTag: []string{"redirect", "socks"}, OutboundTag: mainTag},
	)

	routeJSON, err := json.MarshalIndent(map[string]any{"routing": routing}, "", "  ")
	return outJSON, routeJSON, err
}

func buildInbounds() []byte {
	ib := map[string]any{
		"inbounds": []any{
			map[string]any{
				"tag": "redirect", "listen": "0.0.0.0", "port": 61219,
				"protocol": "dokodemo-door",
				"settings": map[string]any{"network": "tcp", "followRedirect": true},
				"sniffing": map[string]any{"enabled": true, "destOverride": []string{"http", "tls", "quic"}},
			},
			map[string]any{
				"tag": "guest", "listen": "0.0.0.0", "port": 61220,
				"protocol": "dokodemo-door",
				"settings": map[string]any{"network": "tcp", "followRedirect": true},
				"sniffing": map[string]any{"enabled": true, "destOverride": []string{"http", "tls", "quic"}},
			},
			map[string]any{
				"tag": "socks", "listen": "127.0.0.1", "port": 1082,
				"protocol": "socks",
				"settings": map[string]any{"auth": "noauth", "udp": false},
			},
			map[string]any{
				"tag": "dns-in", "listen": "127.0.0.1", "port": 5354,
				"protocol": "dokodemo-door",
				"settings": map[string]any{"address": "1.1.1.1", "port": 53, "network": "tcp,udp"},
			},
		},
	}
	b, _ := json.MarshalIndent(ib, "", "  ")
	return b
}

// ---------------------------------------------------------------- сеть

func fetch(urlStr string, viaSocks bool) ([]byte, error) {
	client := &http.Client{Timeout: 60 * time.Second}
	if viaSocks {
		client.Transport = &http.Transport{
			Proxy: func(*http.Request) (*url.URL, error) {
				return url.Parse("socks5://127.0.0.1:1082")
			},
			DialContext: (&net.Dialer{Timeout: 20 * time.Second}).DialContext,
		}
	}
	req, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "v2rayN/6.31")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
}

func publicIP() (string, error) {
	client := &http.Client{
		Timeout: 12 * time.Second,
		Transport: &http.Transport{
			Proxy: func(*http.Request) (*url.URL, error) { return url.Parse("socks5://127.0.0.1:1082") },
		},
	}
	resp, err := client.Get("https://api.ipify.org")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 64))
	ip := strings.TrimSpace(string(b))
	if ip == "" {
		return "", errors.New("пустой ответ")
	}
	return ip, nil
}

func tcpAlive(host string, port int) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), 3*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func outboundAddr(o Outbound) (string, int) {
	if v, ok := o.Settings["vnext"].([]any); ok && len(v) > 0 {
		if m, ok := v[0].(map[string]any); ok {
			host, _ := m["address"].(string)
			port := toInt(m["port"])
			return host, port
		}
	}
	if v, ok := o.Settings["servers"].([]any); ok && len(v) > 0 {
		if m, ok := v[0].(map[string]any); ok {
			host, _ := m["address"].(string)
			return host, toInt(m["port"])
		}
	}
	return "", 0
}

func toInt(v any) int {
	switch t := v.(type) {
	case float64:
		return int(t)
	case int:
		return t
	case string:
		n, _ := strconv.Atoi(t)
		return n
	}
	return 0
}

// ---------------------------------------------------------------- действия

func restartXray(p paths) {
	for _, s := range []string{"S24xray", "S99xkeen", "xkeen"} {
		script := filepath.Join(p.Root, "etc", "init.d", s)
		if _, err := os.Stat(script); err == nil {
			exec.Command(script, "restart").Run()
			return
		}
	}
	exec.Command("sh", "-c", "killall xray 2>/dev/null; sleep 1; "+filepath.Join(p.Root, "sbin", "xray")+" run -confdir "+p.Config+" >/dev/null 2>&1 &").Run()
}

func testConfig(p paths) error {
	cmd := exec.Command(filepath.Join(p.Root, "sbin", "xray"), "run", "-test", "-confdir", p.Config)
	cmd.Env = append(os.Environ(), "XRAY_LOCATION_ASSET="+filepath.Join(p.Xray, "dat"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// writeAtomic пишет файл через временный, чтобы не оставить полузаписанный конфиг.
func writeAtomic(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func applyConfig(p paths, outs []Outbound, route string) (string, error) {
	outJSON, routeJSON, err := buildConfig(outs, route)
	if err != nil {
		return "", err
	}
	os.MkdirAll(p.Config, 0o755)

	// сначала сохраняем то, что работает сейчас: без резерва не трогаем
	backup := filepath.Join(p.Work, "backup-"+time.Now().Format("20060102-150405"))
	for _, name := range []string{"04_outbounds.json", "05_routing.json", "01_inbounds.json"} {
		src := filepath.Join(p.Config, name)
		if b, err := os.ReadFile(src); err == nil {
			os.MkdirAll(backup, 0o755)
			os.WriteFile(filepath.Join(backup, name), b, 0o644)
		}
	}

	if _, err := os.Stat(filepath.Join(p.Config, "01_inbounds.json")); err != nil {
		writeAtomic(filepath.Join(p.Config, "01_inbounds.json"), buildInbounds())
	}
	if err := writeAtomic(filepath.Join(p.Config, "04_outbounds.json"), outJSON); err != nil {
		restoreBackup(p, backup)
		return "", err
	}
	if err := writeAtomic(filepath.Join(p.Config, "05_routing.json"), routeJSON); err != nil {
		restoreBackup(p, backup)
		return "", err
	}
	return outs[0].Tag, nil
}

// restoreBackup возвращает конфиги, которые работали до нас.
func restoreBackup(p paths, backup string) {
	entries, err := os.ReadDir(backup)
	if err != nil {
		return
	}
	for _, e := range entries {
		if b, err := os.ReadFile(filepath.Join(backup, e.Name())); err == nil {
			writeAtomic(filepath.Join(p.Config, e.Name()), b)
		}
	}
	p.log("конфиги восстановлены из %s", backup)
}

func cmdInstall(p paths, subURL, route string, skipRestart bool) error {
	os.MkdirAll(p.Work, 0o755)
	os.MkdirAll(filepath.Dir(p.Log), 0o755)

	if subURL == "" {
		if b, err := os.ReadFile(p.subURLFile()); err == nil {
			subURL = strings.TrimSpace(string(b))
		}
	}
	if subURL == "" {
		return errors.New("не задан адрес подписки: --sub URL или файл /opt/etc/xray/sub.url")
	}
	os.WriteFile(p.subURLFile(), []byte(subURL+"\n"), 0o600)

	if err := ensureXray(p); err != nil {
		return err
	}

	p.log("скачиваю подписку")
	raw, err := fetch(subURL, false)
	if err != nil {
		p.log("прямой путь не сработал (%v), пробую через туннель", err)
		raw, err = fetch(subURL, true)
		if err != nil {
			return fmt.Errorf("подписка недоступна ни напрямую, ни через туннель: %v", err)
		}
	}

	outs, _, err := loadSubscription(raw)
	if err != nil {
		return err
	}
	p.log("в подписке серверов: %d", len(outs))

	// оставляем текущий сервер первым, если он ещё есть в подписке
	if cur, err := os.ReadFile(p.tagFile()); err == nil {
		tag := strings.TrimSpace(string(cur))
		for i, o := range outs {
			if o.Tag == tag && i != 0 {
				outs[0], outs[i] = outs[i], outs[0]
				p.log("текущий сервер пробуем первым: %s", tag)
				break
			}
		}
	}

	var lastErr error
	for i := 0; i < len(outs); i++ {
		ordered := append([]Outbound{outs[i]}, append(append([]Outbound{}, outs[:i]...), outs[i+1:]...)...)
		host, port := outboundAddr(ordered[0])
		if !tcpAlive(host, port) {
			p.log("%s: адрес не отвечает, пропускаем", ordered[0].Tag)
			continue
		}
		tag, err := applyConfig(p, ordered, route)
		if err != nil {
			lastErr = err
			continue
		}
		if err := testConfig(p); err != nil {
			p.log("%s: конфиг не проходит проверку: %v", tag, err)
			lastErr = err
			continue
		}
		if !skipRestart {
			restartXray(p)
			time.Sleep(4 * time.Second)
			ip, err := publicIP()
			if err != nil {
				p.log("%s: туннель не ответил (%v)", tag, err)
				lastErr = err
				continue
			}
			p.log("работает через %s, внешний IP %s", tag, ip)
		}
		os.WriteFile(p.tagFile(), []byte(tag), 0o644)
		os.WriteFile(p.lastJSON(), []byte(fmt.Sprintf("%d серверов, %s", len(outs), tag)), 0o644)
		return nil
	}
	return fmt.Errorf("ни один сервер не поднялся: %v", lastErr)
}

func cmdSync(p paths, route string) error {
	before, _ := os.ReadFile(p.tagFile())
	err := cmdInstall(p, "", route, false)
	if err != nil {
		p.log("обновление не удалось: %v — оставляю прежний конфиг, повтор через 10 минут", err)
		time.Sleep(10 * time.Minute)
		return cmdSync(p, route)
	}
	after, _ := os.ReadFile(p.tagFile())
	if string(before) != string(after) {
		p.log("сервер сменился: %s → %s", strings.TrimSpace(string(before)), strings.TrimSpace(string(after)))
	}
	return nil
}

func cmdHealth(p paths) error {
	if _, err := publicIP(); err == nil {
		return nil
	}
	p.log("туннель молчит, ищу новый сервер")
	return cmdSync(p, "ru-direct")
}

func cmdGuard(p paths, every, syncEvery time.Duration) error {
	p.log("сторож запущен: проверка каждые %s, подписка каждые %s", every, syncEvery)
	last := time.Now()
	for {
		cmdHealth(p)
		if time.Since(last) >= syncEvery {
			last = time.Now()
			cmdSync(p, "ru-direct")
		}
		time.Sleep(every)
	}
}

func cmdStatus(p paths) error {
	tag, _ := os.ReadFile(p.tagFile())
	fmt.Printf("активный сервер: %s\n", firstNonEmpty(strings.TrimSpace(string(tag)), "не выбран"))
	if ip, err := publicIP(); err == nil {
		fmt.Printf("внешний IP через туннель: %s\n", ip)
	} else {
		fmt.Printf("туннель: не отвечает (%v)\n", err)
	}
	if b, err := os.ReadFile(p.subURLFile()); err == nil {
		fmt.Printf("подписка: %s\n", maskURL(strings.TrimSpace(string(b))))
	}
	if b, err := os.ReadFile(p.lastJSON()); err == nil {
		fmt.Printf("последнее состояние: %s\n", string(b))
	}
	return nil
}

func maskURL(s string) string {
	if len(s) < 24 {
		return "задана"
	}
	return s[:18] + "…" + s[len(s)-4:]
}

// ---------------------------------------------------------------- main

func main() {
	if len(os.Args) < 2 {
		usage()
		return
	}
	p := defaultPaths()
	route := "ru-direct"

	switch os.Args[1] {
	case "install":
		fs := flag.NewFlagSet("install", flag.ExitOnError)
		sub := fs.String("sub", "", "адрес подписки")
		rt := fs.String("route", "ru-direct", "ru-direct | all")
		skip := fs.Bool("skip-restart", false, "собрать конфиг, но не перезапускать xray (для проверки)")
		fs.Parse(os.Args[2:])
		route = *rt
		if err := cmdInstall(p, *sub, route, *skip); err != nil {
			p.log("ОШИБКА: %v", err)
			os.Exit(1)
		}

	case "sync":
		if err := cmdSync(p, route); err != nil {
			os.Exit(1)
		}

	case "health":
		cmdHealth(p)

	case "guard":
		fs := flag.NewFlagSet("guard", flag.ExitOnError)
		every := fs.Duration("every", 5*time.Minute, "как часто проверять туннель")
		syncEvery := fs.Duration("sync-every", 30*time.Minute, "как часто обновлять подписку")
		fs.Parse(os.Args[2:])
		cmdGuard(p, *every, *syncEvery)

	case "firewall":
		fs := flag.NewFlagSet("firewall", flag.ExitOnError)
		lan := fs.String("lan", "192.168.2.0/24", "адрес основной сети")
		guest := fs.String("guest", "10.1.30.0/24", "адрес гостевой сети")
		mark := fs.String("mark", "", "метка политики для гостевых клиентов (необязательно)")
		fs.Parse(os.Args[2:])
		if err := cmdFirewall(fwConf{
			LAN: *lan, Guest: *guest, GuestMark: *mark,
			Redirect: 61219, GuestPort: 61220, DNSPort: 5354,
		}); err != nil {
			fmt.Println("ОШИБКА:", err)
			os.Exit(1)
		}
		fmt.Println("правила применены")

	case "status":
		cmdStatus(p)

	case "gen":
		// офлайн-проверка: разобрать файл подписки и собрать конфиг в каталог
		fs := flag.NewFlagSet("gen", flag.ExitOnError)
		sub := fs.String("sub", "", "файл с подпиской")
		out := fs.String("out", "out", "куда сложить конфиги")
		fs.Parse(os.Args[2:])
		raw, err := os.ReadFile(*sub)
		if err != nil {
			fmt.Println("не читается файл:", err)
			os.Exit(1)
		}
		outs, _, err := loadSubscription(raw)
		if err != nil {
			fmt.Println("ОШИБКА:", err)
			os.Exit(1)
		}
		os.MkdirAll(*out, 0o755)
		outJSON, routeJSON, _ := buildConfig(outs, route)
		writeAtomic(filepath.Join(*out, "04_outbounds.json"), outJSON)
		writeAtomic(filepath.Join(*out, "05_routing.json"), routeJSON)
		writeAtomic(filepath.Join(*out, "01_inbounds.json"), buildInbounds())
		fmt.Printf("серверов: %d, первый: %s\nконфиги в %s\n", len(outs), outs[0].Tag, *out)

	default:
		usage()
	}
}

func usage() {
	fmt.Print(`keen-xray — Xray на Keenetic без ручной правки конфигов

  keen-xray install --sub URL [--route ru-direct|all]
  keen-xray sync
  keen-xray health
  keen-xray guard [--every 5m] [--sync-every 30m]
  keen-xray status
  keen-xray gen --sub файл --out каталог     (проверка без роутера)

Поддерживаются подписки: JSON (Liberty, v2rayN) и обычные base64-списки
vless:// vmess:// trojan://.
`)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
