#!/bin/sh
# Гостевая сеть (10.1.30.0/24) и помеченные политикой клиенты:
#   весь TCP -> Xray :61220, DNS -> Xray :5354, IPv6 режется.
CHAIN="guestxray"
NET="10.1.30.0/24"
MARK="0xffffaac"
MASK="0xfffffff"

[ -x /opt/sbin/xray ] || exit 0
command -v iptables >/dev/null 2>&1 || exit 0

iptables -t nat -N "$CHAIN" 2>/dev/null
iptables -t nat -F "$CHAIN" 2>/dev/null

# DNS первым делом
iptables -t nat -A "$CHAIN" -p udp --dport 53 -j REDIRECT --to-ports 5354
iptables -t nat -A "$CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports 5354

for net in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
           172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
    iptables -t nat -A "$CHAIN" -d "$net" -j RETURN
done
iptables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports 61220

# 1) по адресу гостевой подсети
iptables -t nat -D PREROUTING -s "$NET" -j "$CHAIN" 2>/dev/null
iptables -t nat -I PREROUTING 1 -s "$NET" -j "$CHAIN"

# 2) по метке политики
iptables -t nat -D PREROUTING -m connmark --mark "$MARK/$MASK" -j "$CHAIN" 2>/dev/null
iptables -t nat -I PREROUTING 2 -m connmark --mark "$MARK/$MASK" -j "$CHAIN"

# 3) основная сеть: DNS -> Xray :5354 (без утечки), 80/443 -> цепочка XKeen
iptables -t nat -N lanxray 2>/dev/null
iptables -t nat -F lanxray 2>/dev/null
iptables -t nat -A lanxray -p udp --dport 53 -j REDIRECT --to-ports 5354
iptables -t nat -A lanxray -p tcp --dport 53 -j REDIRECT --to-ports 5354
iptables -t nat -A lanxray -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 61219
iptables -t nat -A lanxray -j RETURN

iptables -t nat -D PREROUTING -s 192.168.2.0/24 -j lanxray 2>/dev/null
iptables -t nat -I PREROUTING 3 -s 192.168.2.0/24 -j lanxray

# IPv6 гостям закрываем
ip6tables -N guestxray6 2>/dev/null
ip6tables -F guestxray6 2>/dev/null
ip6tables -A guestxray6 -j DROP
ip6tables -D FORWARD -m connmark --mark "$MARK/$MASK" -j guestxray6 2>/dev/null
ip6tables -I FORWARD 1 -m connmark --mark "$MARK/$MASK" -j guestxray6

# --- QUIC и IPv6: не даём обойти туннель ---
# UDP 443 (QUIC) не проксируется: роняем, клиент сам уйдёт на TCP через туннель
iptables -N lanquic 2>/dev/null
iptables -F lanquic 2>/dev/null
iptables -A lanquic -p udp --dport 443 -j DROP
iptables -A lanquic -j RETURN
for net in 192.168.2.0/24 10.1.30.0/24; do
    iptables -D FORWARD -s "$net" -j lanquic 2>/dev/null
    iptables -I FORWARD 1 -s "$net" -j lanquic
done

# IPv6 из локальных сетей наружу не пускаем — иначе адрес утекает мимо прокси
ip6tables -N lan6 2>/dev/null
ip6tables -F lan6 2>/dev/null
ip6tables -A lan6 -j DROP
for br in Bridge0 Bridge1; do
    ip6tables -D FORWARD -i "$br" -j lan6 2>/dev/null
    ip6tables -I FORWARD 1 -i "$br" -j lan6
done
