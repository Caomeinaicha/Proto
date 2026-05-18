#!/bin/bash
set -e

echo "=== Configure systemd-resolved DNS ==="

sudo mkdir -p /etc/systemd/resolved.conf.d

sudo tee /etc/systemd/resolved.conf.d/custom.conf > /dev/null << 'CONFIG'
[Resolve]
DNS=8.8.8.8 1.1.1.1 2001:4860:4860::8888 2606:4700:4700::1111
FallbackDNS=9.9.9.9 2620:fe::fe
DNSOverTLS=no
Cache=yes
CONFIG

echo "-> DNS configuration written."

echo "=== Restart systemd-resolved ==="

sudo systemctl restart systemd-resolved

echo "-> systemd-resolved restarted."

echo "=== Current DNS Status ==="

resolvectl status

echo
echo "Done."
echo "Recommended: reboot"