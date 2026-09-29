#!/usr/bin/env bash
set -Eeuo pipefail

# Edit these values before running the installer.
GADGET_NAME="bgwxgadget"
USB_CONNECTION_NAME="bgwxgadget"
HOTSPOT_CONNECTION_NAME="bgwxgadget hotspot"
HOTSPOT_SSID="bgwxgadgethotspot"
HOTSPOT_PASSWORD="coolboy123"
WIFI_INTERFACE="wlan0"
ETH_INTERFACE="eth0"
ETH_DHCP_NAME="eth0-dhcp"
ETH_LINK_LOCAL_NAME="eth0-zeroconf"
USB_MANUFACTURER="BGW"
USB_PRODUCT="BGW-USB GADGET"
USB_SERIAL="6666666666"

if (( EUID != 0 )); then
    printf 'Run this installer with sudo: sudo bash %s\n' "$0" >&2
    exit 1
fi

if [[ ! "$GADGET_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo 'GADGET_NAME may contain only letters, numbers, _, . and -' >&2
    exit 1
fi
if ((${#HOTSPOT_PASSWORD} < 8 || ${#HOTSPOT_PASSWORD} > 63)); then
    echo 'HOTSPOT_PASSWORD must be 8 to 63 characters.' >&2
    exit 1
fi
for command_name in nmcli systemctl modprobe; do
    command -v "$command_name" >/dev/null || {
        printf 'Missing command: %s\n' "$command_name" >&2
        exit 1
    }
done
for boot_file in /boot/firmware/cmdline.txt /boot/firmware/config.txt; do
    [[ -f "$boot_file" ]] || {
        printf 'Missing Raspberry Pi boot file: %s\n' "$boot_file" >&2
        exit 1
    }
done

mkdir -p /boot/firmware/bak
for filename in cmdline.txt config.txt; do
    if [[ ! -e "/boot/firmware/bak/$filename" ]]; then
        cp "/boot/firmware/$filename" "/boot/firmware/bak/$filename"
    fi
done
if ! grep -Eq '(^|[[:space:]])modules-load=dwc2([,[:space:]]|$)' /boot/firmware/cmdline.txt; then
    sed -i '1s/$/ modules-load=dwc2/' /boot/firmware/cmdline.txt
fi
if ! grep -Fxq 'dtoverlay=dwc2,dr_mode=peripheral' /boot/firmware/config.txt; then
    printf '\n%s\n' 'dtoverlay=dwc2,dr_mode=peripheral' >> /boot/firmware/config.txt
fi
if ! grep -Fxq 'libcomposite' /etc/modules; then
    printf '%s\n' 'libcomposite' >> /etc/modules
fi

# The launcher and fallback service share this configuration.
{
    for name in GADGET_NAME USB_CONNECTION_NAME HOTSPOT_CONNECTION_NAME \
        WIFI_INTERFACE USB_MANUFACTURER USB_PRODUCT USB_SERIAL; do
        printf '%s=%q\n' "$name" "${!name}"
    done
} > /etc/default/bgwxgadget
chmod 600 /etc/default/bgwxgadget

cat > /usr/local/sbin/bgwxgadget-launch <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail
source /etc/default/bgwxgadget
modprobe libcomposite
G="/sys/kernel/config/usb_gadget/$GADGET_NAME"
mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/ecm.usb0"
printf '%s' '0x1d6b' > "$G/idVendor"
printf '%s' '0x0104' > "$G/idProduct"
printf '%s' '0x0100' > "$G/bcdDevice"
printf '%s' '0x0200' > "$G/bcdUSB"
printf '%s' "$USB_SERIAL" > "$G/strings/0x409/serialnumber"
printf '%s' "$USB_MANUFACTURER" > "$G/strings/0x409/manufacturer"
printf '%s' "$USB_PRODUCT" > "$G/strings/0x409/product"
printf '%s' 'Config 1: ECM network' > "$G/configs/c.1/strings/0x409/configuration"
printf '%s' '250' > "$G/configs/c.1/MaxPower"
printf '%s' '66:22:33:44:55:66' > "$G/functions/ecm.usb0/host_addr"
printf '%s' '92:22:33:44:55:66' > "$G/functions/ecm.usb0/dev_addr"
if [[ ! -L "$G/configs/c.1/ecm.usb0" ]]; then
    ln -s "$G/functions/ecm.usb0" "$G/configs/c.1/ecm.usb0"
fi
if [[ -z $(cat "$G/UDC") ]]; then
    udc=$(find /sys/class/udc -mindepth 1 -maxdepth 1 -printf '%f\n' | head -n 1)
    if [[ -z "$udc" ]]; then
        echo 'No USB device controller found. Check the Pi model and USB port.' >&2
        exit 1
    fi
    printf '%s' "$udc" > "$G/UDC"
fi
nmcli device set usb0 managed yes
LAUNCH
chmod 755 /usr/local/sbin/bgwxgadget-launch

cat > /etc/systemd/system/bgwxgadget.service <<'SERVICE'
[Unit]
Description=BGW USB ECM gadget
After=systemd-modules-load.service NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/bgwxgadget-launch

[Install]
WantedBy=multi-user.target
SERVICE

# Create a profile once; subsequent runs update it.
ensure_connection() {
    local connection_name=$1
    local connection_type=$2
    local interface_name=$3
    shift 3
    if nmcli -g connection.id connection show "$connection_name" >/dev/null 2>&1; then
        nmcli connection modify "$connection_name" \
            connection.interface-name "$interface_name" "$@"
    else
        nmcli connection add con-name "$connection_name" \
            type "$connection_type" ifname "$interface_name" "$@"
    fi
}
ensure_connection "$USB_CONNECTION_NAME" \
    ethernet usb0 ipv4.method shared ipv6.method shared \
    connection.autoconnect yes connection.autoconnect-priority 10
ensure_connection "$HOTSPOT_CONNECTION_NAME" \
    wifi "$WIFI_INTERFACE" \
    802-11-wireless.mode ap 802-11-wireless.ssid "$HOTSPOT_SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASSWORD" \
    ipv4.method shared ipv6.method disabled connection.autoconnect no
ensure_connection "$ETH_DHCP_NAME" \
    ethernet "$ETH_INTERFACE" ipv4.method auto \
    connection.autoconnect yes connection.autoconnect-priority 2 \
    connection.autoconnect-retries 2
ensure_connection "$ETH_LINK_LOCAL_NAME" \
    ethernet "$ETH_INTERFACE" ipv4.method link-local \
    ipv6.method disabled connection.autoconnect yes \
    connection.autoconnect-priority 1

cat > /usr/local/sbin/bgwxgadget-hotspot-fallback <<'FALLBACK'
#!/usr/bin/env bash
set -Eeuo pipefail
source /etc/default/bgwxgadget
usb_ready=false
if [[ -r /sys/class/net/usb0/carrier ]] &&
   [[ $(cat /sys/class/net/usb0/carrier) == 1 ]]; then
    usb_connection=$(nmcli -g GENERAL.CONNECTION device show usb0 2>/dev/null || true)
    [[ "$usb_connection" == "$USB_CONNECTION_NAME" ]] && usb_ready=true
fi
wifi_connection=$(nmcli -g GENERAL.CONNECTION device show "$WIFI_INTERFACE" 2>/dev/null || true)
if [[ "$usb_ready" == true ]]; then
    if [[ "$wifi_connection" == "$HOTSPOT_CONNECTION_NAME" ]]; then
        nmcli connection down "$HOTSPOT_CONNECTION_NAME"
        logger -t bgwxgadget 'USB Ethernet connected; hotspot stopped'
    fi
elif [[ -z "$wifi_connection" || "$wifi_connection" == '--' ]]; then
    nmcli connection up "$HOTSPOT_CONNECTION_NAME" ifname "$WIFI_INTERFACE"
    logger -t bgwxgadget 'USB Ethernet disconnected; hotspot started'
fi
FALLBACK
chmod 755 /usr/local/sbin/bgwxgadget-hotspot-fallback

cat > /etc/systemd/system/bgwxgadget-hotspot-fallback.service <<'SERVICE'
[Unit]
Description=Switch BGW hotspot according to USB Ethernet link
After=NetworkManager.service bgwxgadget.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bgwxgadget-hotspot-fallback
SERVICE

cat > /etc/systemd/system/bgwxgadget-hotspot-fallback.timer <<'TIMER'
[Unit]
Description=Check BGW USB Ethernet and hotspot state

[Timer]
OnBootSec=20s
OnUnitActiveSec=5s
AccuracySec=1s
Unit=bgwxgadget-hotspot-fallback.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable bgwxgadget.service
systemctl enable --now bgwxgadget-hotspot-fallback.timer
printf '\nInstalled. Reboot, then check:\n  systemctl status bgwxgadget.service\n  systemctl status bgwxgadget-hotspot-fallback.timer\n  nmcli connection show\n'
