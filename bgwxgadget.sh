#!/bin/bash
#Make sure the permissions on the script and the service file are correct. They should #be owned by root and the script should be executable.
# chmod 744 /home/bgw/libc_usb/start.sh
# chmod 644 /etc/systemd/system/libc_usb.service
apt update -y
apt full-upgrade -y
apt install -y dhcpcd

mkdir /boot/firmware/bak
cp /etc/modules /boot/firmware/bak/bak_etcmodules
cp /boot/firmware/cmdline.txt /boot/firmware/bak/bak_cmdline.txt
cp /boot/firmware/config.txt /boot/firmware/bak/bak_config.txt

CMDLINE_FILE="/boot/firmware/cmdline.txt"
INSERT_TEXT="modules-load=dwc2"
AFTER_WORD="rootwait"

# Check if it's already there
if grep -qw "$INSERT_TEXT" "$CMDLINE_FILE"; then
    echo "ℹ '$INSERT_TEXT' already present in $CMDLINE_FILE"
else
    # Insert after 'rootwait'
    sed -i "s/\b$AFTER_WORD\b/& $INSERT_TEXT/" "$CMDLINE_FILE"
    echo "✔ Inserted '$INSERT_TEXT' after '$AFTER_WORD'"
fi
echo "libcomposite" >> /etc/modules
#echo " modules-load=dwc2"  >> /boot/firmware/cmdline.txt
echo "dtoverlay=dwc2" >> /boot/firmware/config.txt

 mkdir /home/bgw/bgwxgadget
 touch /home/bgw/bgwxgadget/launch.sh
 chmod 744 /home/bgw/bgwxgadget/launch.sh
 chmod a+x /home/bgw/bgwxgadget/launch.sh
# nano /home/bgw/bgwxgadget/launch.sh
echo "#!/bin/bash
modprobe libcomposite
mkdir -p /sys/kernel/config/usb_gadget/bgwxgadget
cd /sys/kernel/config/usb_gadget/bgwxgadget
echo 0x1d6b > /sys/kernel/config/usb_gadget/bgwxgadget/idVendor
echo 0x0104 > /sys/kernel/config/usb_gadget/bgwxgadget/idProduct
echo 0x0100 > /sys/kernel/config/usb_gadget/bgwxgadget/bcdDevice
echo 0x0200 > /sys/kernel/config/usb_gadget/bgwxgadget/bcdUSB
mkdir -p /sys/kernel/config/usb_gadget/bgwxgadget/strings/0x409
echo "6666666666" > /sys/kernel/config/usb_gadget/bgwxgadget/strings/0x409/serialnumber
echo "BGW" > /sys/kernel/config/usb_gadget/bgwxgadget/strings/0x409/manufacturer
echo "BGW-USB GADGET" > /sys/kernel/config/usb_gadget/bgwxgadget/strings/0x409/product
mkdir -p /sys/kernel/config/usb_gadget/bgwxgadget/configs/c.1/strings/0x409
echo "Config 1: ECM network" > /sys/kernel/config/usb_gadget/bgwxgadget/configs/c.1/strings/0x409/configuration
echo 250 > /sys/kernel/config/usb_gadget/bgwxgadget/configs/c.1/MaxPower
mkdir -p /sys/kernel/config/usb_gadget/bgwxgadget/functions/ecm.usb0
echo "66:22:33:44:55:66" > /sys/kernel/config/usb_gadget/bgwxgadget/functions/ecm.usb0/host_addr
echo "99:22:33:44:55:66" > /sys/kernel/config/usb_gadget/bgwxgadget/functions/ecm.usb0/dev_addr
ln -s /sys/kernel/config/usb_gadget/bgwxgadget/functions/ecm.usb0 configs/c.1/
ls /sys/class/udc > UDC 
nmcli device set usb0 managed true
nmcli connection up bgwxgadget"  >> /home/bgw/bgwxgadget/launch.sh



# touch /lib/systemd/system/bgwxgadget.service
# chmod a+x /lib/systemd/system/bgwxgadget.service
echo "
[Unit]
Description=BGW-Gadget - USB Gadget
After=network-online.target
Wants=network-online.target
#After=systemd-modules-load.service
[Service]
User=root
Group=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/home/bgw/bgwxgadget/launch.sh
[Install]
WantedBy=sysinit.target" > /lib/systemd/system/bgwxgadget.service

 systemctl enable bgwxgadget.service
 systemctl start bgwxgadget.service
# systemctl status bgwxgadget.service


CONF_FILE="/etc/NetworkManager/NetworkManager.conf"
AFTER_WORD="[main]"
LINE_TO_INSERT="dhcp=dhcpcd"

# Escape square brackets for use in sed regex
AFTER_WORD_ESCAPED=$(printf '%s\n' "$AFTER_WORD" | sed 's/[][\^$.*/]/\\&/g')

# Check if line already exists to avoid duplicate insertion
if ! grep -Fxq "$LINE_TO_INSERT" "$CONF_FILE"; then
    # Insert after line matching $AFTER_WORD
    sed -i "/^$AFTER_WORD_ESCAPED\$/a$LINE_TO_INSERT" "$CONF_FILE"
    echo "✔ Inserted '$LINE_TO_INSERT' after [$AFTER_WORD]"
else
    echo "ℹ '$LINE_TO_INSERT' already exists in $CONF_FILE"
fi


touch /home/bgw/bgwxgadget/run_once_script.sh
chmod a+x /home/bgw/bgwxgadget/run_once_script.sh
echo "
#!/bin/bash

nmcli connection add ifname usb0 ipv4.method shared ipv6.method shared autoconnect yes connection.autoconnect-priority 10 con-name bgwxgadget type ethernet
nmcli device wifi hotspot ssid bgwxdeskpi password coolboy123
nmcli connection modify "Hotspot" autoconnect yes connection.autoconnect-priority 10
nmcli connection modify "preconfigured" connection.autoconnect-priority 5
echo "setting up fallback-to-zero-conf setup!"
nmcli connection add con-name eth0-dhcp ifname eth0 type ethernet connection.autoconnect-priority 2 connection.autoconnect-retries 2
nmcli con add con-name eth0-zeroconf type ethernet ifname eth0 connection.autoconnect-priority 1 ipv4.method link-local ipv4.link-local enabled
nmcli connection reload
" > /home/bgw/bgwxgadget/run_once_script.sh

/home/bgw/bgwxgadget/run_once_script.sh