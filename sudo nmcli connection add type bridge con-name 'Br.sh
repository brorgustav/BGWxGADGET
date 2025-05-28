sudo nmcli connection add type bridge con-name 'Bridge' ifname bridge0
sudo nmcli connection modify 'bgwxdeskpi' master bridge0
sudo nmcli connection modify 'preconfigured' master bridge0
sudo nmcli connection add type ethernet slave-type bridge \
    con-name 'bgwxgadget' ifname usb0 master bridge0


    sudo nmcli c delete bgwxhotspot
    sudo nmcli connection add con-name 'bgwxhotspot' \
    ifname wlan0 type wifi slave-type bridge master bridge0 \
    wifi.mode ap wifi.ssid bgwxhotspot wifi-sec.key-mgmt wpa-psk \
    wifi-sec.proto rsn wifi-sec.pairwise ccmp \
    wifi-sec.psk coolboy123



sudo nmcli connection add type bridge con-name 'Bridge' ifname bridge0
sudo nmcli connection add ifname usb0 autoconnect yes con-name bgwxgadget type ethernet
sudo nmcli device wifi hotspot ssid bgwxdeskpi password coolboy123
sudo nmcli connection modify 'bgwxgadget' master bridge0
sudo nmcli connection modify 'preconfigured' master bridge0
sudo nmcli connection modify 'Wired connection 1' master bridge0
sudo nmcli connection modify "hotspot" connection.autoconnect-priority 10
sudo nmcli connection modify "preconfigured" connection.autoconnect-priority 5