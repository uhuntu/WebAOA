#!/bin/sh
# Installs the udev rules so Chrome can open the phone over WebUSB.
set -e
dir=$(dirname "$0")
sudo cp "$dir/52-webaoa.rules" /etc/udev/rules.d/52-webaoa.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "Installed. Replug the phone and reload the page."
