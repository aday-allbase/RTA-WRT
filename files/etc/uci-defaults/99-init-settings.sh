#!/bin/sh

# Create a log file with timestamp
LOGFILE="/root/setup_$(date +%Y%m%d_%H%M%S).log"
exec > "$LOGFILE" 2>&1

# Function for logging with timestamps
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# System information banner
log "==================== SYSTEM INFORMATION ===================="
log "Installed Time: $(date '+%A, %d %B %Y %T')"
log "Processor: $(ubus call system board | grep '\"system\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
log "Device Model: $(ubus call system board | grep '\"model\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
log "Device Board: $(ubus call system board | grep '\"board_name\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
log "Memory: $(free -m | grep Mem | awk '{print $2}') MB"
log "Storage: $(df -h / | tail -1 | awk '{print $2}')"
log "==================== CONFIGURATION START ===================="

# Backup original configuration
log "Creating configuration backup..."
mkdir -p /root/config_backup
cp -r /etc/config/* /root/config_backup/
cp /etc/openwrt_release /root/config_backup/

# Firmware customization
log "Customizing firmware information..."
sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' build OPEN-WRT [ Ouc3kNF6 ]':''),#g" /www/luci-static/resources/view/status/include/10_system.js
sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" /www/luci-static/resources/view/status/include/29_ports.js

# Detect and configure for specific OpenWrt distributions
if grep -q "ImmortalWrt" /etc/openwrt_release; then
  log "ImmortalWrt detected, applying specific configurations..."
  sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  sed -i -E "s|services/ttyd|system/ttyd|g" /usr/share/ucode/luci/template/themes/material/header.ut
  sed -i -E "s|services/ttyd|system/ttyd|g" /usr/lib/lua/luci/view/themes/argon/header.htm
  log "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
elif grep -q "OpenWrt" /etc/openwrt_release; then
  log "OpenWrt detected, applying specific configurations..."
  sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  log "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
fi

# Log installed tunnel applications
log "Tunnel Applications Installed: $(opkg list-installed | grep -e luci-app-openclash -e luci-app-nikki -e luci-app-passwall -e luci-app-clash -e luci-app-shadowsocks | awk '{print $1}' | tr '\n' ' ')"

# System user configuration
log "Setting up root password..."
(echo "root"; sleep 1; echo "root") | passwd > /dev/null

# Time zone and NTP configuration
log "Setting up time zone to Asia/Jakarta and NTP servers..."
uci set system.@system[0].hostname='OPEN-WRT'
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci -q delete system.ntp.server
uci add_list system.ntp.server="0.pool.ntp.org"
uci add_list system.ntp.server="1.pool.ntp.org"
uci add_list system.ntp.server="id.pool.ntp.org"
uci add_list system.ntp.server="time.google.com"
uci add_list system.ntp.server="time.cloudflare.com"
uci commit system

# Network interface configuration
log "Configuring network interfaces..."
# LAN configuration
uci set network.lan.ipaddr="192.168.1.1"
uci set network.lan.netmask="255.255.255.0"

# WAN configuration
# Add failover WAN interface
log "Adding failover WAN interface..."
uci set network.wan=interface
uci set network.wan.proto='dhcp'
uci set network.wan.device='eth1'
uci commit network

# Firewall configuration
log "Configuring firewall..."
uci set firewall.@zone[1].network='wan'
uci commit firewall

# Disable IPv6
log "Disabling IPv6..."
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.ndp
uci commit dhcp

# Package management and repositories
log "Setting up package management and repositories..."
# Disable signature check for opkg
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf

# UI configuration
log "Setting up UI configuration..."
# Set material as default theme
uci set luci.main.mediaurlbase='/luci-static/material' && uci commit
echo >> /usr/share/ucode/luci/template/header.ut && cat /usr/share/ucode/luci/template/theme.txt >> /usr/share/ucode/luci/template/header.ut
rm -rf /usr/share/ucode/luci/template/theme.txt

# Configure TTYD
log "Configuring TTYD..."
uci set ttyd.@ttyd[0].command='/bin/bash --login'
uci set ttyd.@ttyd[0].interface='@lan'
uci set ttyd.@ttyd[0].port='7681'
uci commit ttyd

# USB modem configuration - remove problematic USB mode switch entries
log "Configuring USB modem settings..."
# Function to safely edit USB mode switch configuration
edit_usb_mode_json() {
  local vid_pid=$1
  log "Removing USB mode switch for $vid_pid"
  sed -i -e "/$vid_pid/,+5d" /etc/usb-mode.json
}

# Remove specific USB mode switches
edit_usb_mode_json "12d1:15c1" # Huawei ME909s
edit_usb_mode_json "413c:81d7" # DW5821e
edit_usb_mode_json "1e2d:00b3" # Thales MV31-W T99W175

# Disable XMM modem service
log "Disabling XMM modem service..."
uci set xmm-modem.@xmm-modem[0].enable='0'
uci commit xmm-modem

# Configure vnstat for traffic statistics
log "Setting up vnstat..."
sed -i 's/;DatabaseDir "\/var\/lib\/vnstat"/DatabaseDir "\/etc\/vnstat"/' /etc/vnstat.conf
mkdir -p /etc/vnstat
chmod +x /etc/init.d/vnstat_backup
/etc/init.d/vnstat_backup enable
if [ -f "/www/vnstati/vnstati.sh" ]; then
  chmod +x /www/vnstati/vnstati.sh
  /www/vnstati/vnstati.sh
fi

# Shell environment and profile setup
log "Setting up shell environment..."
sed -i 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' /etc/profile
sed -i 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/#&/' /etc/profile

# Setup utility scripts
log "Setting up utility scripts..."
for script in /usr/bin/openclash.sh; do
  if [ -f "$script" ]; then
    chmod +x "$script"
    log "Made $script executable"
  fi
done

chmod +x /usr/bin/speedtest

# Configure OpenClash if installed
log "Checking and configuring OpenClash..."
if opkg list-installed | grep -q luci-app-openclash; then
  log "OpenClash detected, configuring..."
  # Create directory structure if it doesn't exist
  mkdir -p /etc/openclash/core
  mkdir -p /etc/openclash/history
  
  # Set permissions for core files
  for file in /etc/openclash/core/clash_meta /etc/openclash/GeoIP.dat /etc/openclash/GeoSite.dat /etc/openclash/Country.mmdb; do
    if [ -f "$file" ]; then
      chmod +x "$file"
      log "Set permissions for $file"
    fi
  done
  
  # Apply patches
  if [ -f "/usr/bin/patchoc.sh" ]; then
    chmod +x /usr/bin/patchoc.sh
    log "Patching OpenClash overview..."
    /usr/bin/patchoc.sh
    sed -i '/exit 0/i # OpenClash patch' /etc/rc.local
    sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local
  fi
  
  # Create symbolic links
  ln -sf /etc/openclash/history/config-wrt.db /etc/openclash/cache.db 2>/dev/null
  ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
  
  # Move configuration file
  if [ -f "/etc/config/openclash1" ]; then
    rm -rf /etc/config/openclash
    mv /etc/config/openclash1 /etc/config/openclash
    log "Moved OpenClash configuration file"
  fi
  
  log "OpenClash setup complete!"
else
  log "OpenClash not detected, cleaning up..."
  uci delete internet-detector.Openclash 2>/dev/null
  uci commit internet-detector 2>/dev/null
  service internet-detector restart
  rm -rf /etc/config/openclash1
fi

# Setup PHP for web applications
log "Setting up PHP..."
uci set uhttpd.main.ubus_prefix='/ubus'
uci set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
uci set uhttpd.main.index_page='cgi-bin/luci'
uci add_list uhttpd.main.index_page='index.html'
uci add_list uhttpd.main.index_page='index.php'
uci commit uhttpd

# Optimize PHP configuration
if [ -f "/etc/php.ini" ]; then
  sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
  sed -i -E "s|max_execution_time = [0-9]+|max_execution_time = 60|g" /etc/php.ini
  sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
  sed -i -E "s|;date.timezone =|date.timezone = Asia/Jakarta|g" /etc/php.ini
  log "PHP configuration optimized"
fi

# Create symbolic links for PHP
ln -sf /usr/bin/php-cli /usr/bin/php
[ -d /usr/lib/php8 ] && [ ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php
/etc/init.d/uhttpd restart

# Setup TinyFM file manager
log "Setting up TinyFM file manager..."
mkdir -p /www/tinyfm
ln -sf / /www/tinyfm/rootfs

# Set up system information script
if [ -f "/etc/profile.d/30-sysinfo.sh-bak" ]; then
  rm -rf /etc/profile.d/30-sysinfo.sh 2>/dev/null
  mv /etc/profile.d/30-sysinfo.sh-bak /etc/profile.d/30-sysinfo.sh
  log "Restored original system information script"
fi

# Complete setup
log "==================== CONFIGURATION COMPLETE ===================="
log "All setup tasks completed successfully!"
log "Cleaning up and finalizing..."

# Clean up the setup script
rm -f /etc/uci-defaults/$(basename $0) 2>/dev/null

echo "Setup complete! The system will now reboot in 5 seconds..."
sleep 5
reboot

exit 0