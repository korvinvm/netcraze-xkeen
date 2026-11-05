package main

// Правила перенаправления: основная сеть — только 80/443 в туннель,
// гостевая — весь трафик строго через туннель, DNS всегда через Xray,
// QUIC и IPv6 закрыты, чтобы трафик не утекал мимо.

import (
	"fmt"
	"os/exec"
)

type fwConf struct {
	LAN       string
	Guest     string
	GuestMark string
	Redirect  int
	GuestPort int
	DNSPort   int
}

func run(prog string, args ...string) error {
	cmd := exec.Command(prog, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %v: %v %s", prog, args, err, string(out))
	}
	return nil
}

func tryRun(prog string, args ...string) { _ = run(prog, args...) }

func cmdFirewall(c fwConf) error {
	if _, err := exec.LookPath("iptables"); err != nil {
		return fmt.Errorf("iptables не найден — правила ставить некуда")
	}

	// --- гостевая сеть
	tryRun("iptables", "-t", "nat", "-N", "guestxray")
	tryRun("iptables", "-t", "nat", "-F", "guestxray")

	must := func(prog string, args ...string) error {
		if err := run(prog, args...); err != nil {
			return err
		}
		return nil
	}

	if err := must("iptables", "-t", "nat", "-A", "guestxray", "-p", "udp", "--dport", "53",
		"-j", "REDIRECT", "--to-ports", fmt.Sprint(c.DNSPort)); err != nil {
		return err
	}
	must("iptables", "-t", "nat", "-A", "guestxray", "-p", "tcp", "--dport", "53",
		"-j", "REDIRECT", "--to-ports", fmt.Sprint(c.DNSPort))

	for _, net := range []string{"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
		"169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4"} {
		must("iptables", "-t", "nat", "-A", "guestxray", "-d", net, "-j", "RETURN")
	}
	must("iptables", "-t", "nat", "-A", "guestxray", "-p", "tcp",
		"-j", "REDIRECT", "--to-ports", fmt.Sprint(c.GuestPort))

	tryRun("iptables", "-t", "nat", "-D", "PREROUTING", "-s", c.Guest, "-j", "guestxray")
	must("iptables", "-t", "nat", "-I", "PREROUTING", "1", "-s", c.Guest, "-j", "guestxray")

	if c.GuestMark != "" {
		tryRun("iptables", "-t", "nat", "-D", "PREROUTING", "-m", "connmark",
			"--mark", c.GuestMark, "-j", "guestxray")
		must("iptables", "-t", "nat", "-I", "PREROUTING", "2", "-m", "connmark",
			"--mark", c.GuestMark, "-j", "guestxray")
	}

	// --- основная сеть: DNS и 80/443
	tryRun("iptables", "-t", "nat", "-N", "lanxray")
	tryRun("iptables", "-t", "nat", "-F", "lanxray")
	must("iptables", "-t", "nat", "-A", "lanxray", "-p", "udp", "--dport", "53",
		"-j", "REDIRECT", "--to-ports", fmt.Sprint(c.DNSPort))
	must("iptables", "-t", "nat", "-A", "lanxray", "-p", "tcp", "--dport", "53",
		"-j", "REDIRECT", "--to-ports", fmt.Sprint(c.DNSPort))
	must("iptables", "-t", "nat", "-A", "lanxray", "-p", "tcp", "-m", "multiport",
		"--dports", "80,443", "-j", "REDIRECT", "--to-ports", fmt.Sprint(c.Redirect))
	must("iptables", "-t", "nat", "-A", "lanxray", "-j", "RETURN")

	tryRun("iptables", "-t", "nat", "-D", "PREROUTING", "-s", c.LAN, "-j", "lanxray")
	must("iptables", "-t", "nat", "-I", "PREROUTING", "3", "-s", c.LAN, "-j", "lanxray")

	// --- QUIC не проксируем: роняем, клиент сам уйдёт на TCP через туннель
	tryRun("iptables", "-N", "lanquic")
	tryRun("iptables", "-F", "lanquic")
	must("iptables", "-A", "lanquic", "-p", "udp", "--dport", "443", "-j", "DROP")
	must("iptables", "-A", "lanquic", "-j", "RETURN")
	for _, net := range []string{c.LAN, c.Guest} {
		tryRun("iptables", "-D", "FORWARD", "-s", net, "-j", "lanquic")
		must("iptables", "-I", "FORWARD", "1", "-s", net, "-j", "lanquic")
	}

	// --- IPv6 наружу не пускаем: иначе адрес утекает мимо прокси
	if _, err := exec.LookPath("ip6tables"); err == nil {
		tryRun("ip6tables", "-N", "lan6")
		tryRun("ip6tables", "-F", "lan6")
		must("ip6tables", "-A", "lan6", "-j", "DROP")

		tryRun("ip6tables", "-N", "guestxray6")
		tryRun("ip6tables", "-F", "guestxray6")
		must("ip6tables", "-A", "guestxray6", "-j", "DROP")
		if c.GuestMark != "" {
			tryRun("ip6tables", "-D", "FORWARD", "-m", "connmark", "--mark", c.GuestMark, "-j", "guestxray6")
			must("ip6tables", "-I", "FORWARD", "1", "-m", "connmark", "--mark", c.GuestMark, "-j", "guestxray6")
		}
		ifaces := listBridges()
		for _, br := range ifaces {
			tryRun("ip6tables", "-D", "FORWARD", "-i", br, "-j", "lan6")
			must("ip6tables", "-I", "FORWARD", "1", "-i", br, "-j", "lan6")
		}
	}
	return nil
}

func listBridges() []string {
	out, err := exec.Command("sh", "-c", "ls /sys/class/net | grep -i '^br' || true").Output()
	if err != nil {
		return nil
	}
	var res []string
	cur := ""
	for _, r := range string(out) {
		if r == '\n' {
			if cur != "" {
				res = append(res, cur)
			}
			cur = ""
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		res = append(res, cur)
	}
	return res
}
