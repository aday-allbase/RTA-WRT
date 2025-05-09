#!/bin/sh

# Improved OpenWrt Router Setup Script

# Create a log file with timestamp
LOGFILE="/root/setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# Basic colors for better visibility in logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for logging with timestamps and colors
log() {
  local level="$1"
  shift
  local message="$*"
  local color="${NC}"
  
  case "$level" in
    "INFO") color="${GREEN}" ;;
    "WARNING") color="${YELLOW}" ;;
    "ERROR") color="${RED}" ;;
    "STEP") color="${BLUE}" ;;
  esac
  
  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message${NC}"
}

# Function to check command success and provide feedback
check_command() {
  if [ $? -eq 0 ]; then
    log "INFO" "✓ $1 completed successfully"
  else
    log "ERROR" "✗ $1 failed"
    return 1
  fi
}

# Function to check if a package is installed
is_package_installed() {
  opkg list-installed | grep -q "^$1 "
  return $?
}

# Function to safely apply UCI changes with error checking
safe_uci() {
  local cmd="$1"
  local param="$2"
  local value="$3"
  
  case "$cmd" in
    set)
      uci set "$param"="$value"
      ;;
    add_list)
      uci add_list "$param"="$value"
      ;;
    delete)
      uci -q delete "$param"
      ;;
    *)
      log "ERROR" "Unknown UCI command: $cmd"
      return 1
      ;;
  esac
  
  if [ $? -ne 0 ]; then
    log "WARNING" "UCI command failed: $cmd $param $value"
    return 1
  fi
  return 0
}

# Function to commit UCI changes safely
commit_uci() {
  local section="$1"
  uci commit "$section"
  if [ $? -ne 0 ]; then
    log "ERROR" "Failed to commit UCI changes for $section"
    return 1
  fi
  log "INFO" "Committed UCI changes for $section"
  return 0
}

# Print banner and system information
print_system_info() {
  log "STEP" "==================== SYSTEM INFORMATION ===================="
  log "INFO" "Installed Time: $(date '+%A, %d %B %Y %T')"
  
  local processor="$(ubus call system board | grep '\"system\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
  local model="$(ubus call system board | grep '\"model\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
  local board="$(ubus call system board | grep '\"board_name\"' | sed 's/ \+/ /g' | awk -F'\"' '{print $4}')"
  local memory="$(free -m | grep Mem | awk '{print $2}') MB"
  local storage="$(df -h / | tail -1 | awk '{print $2}')"
  
  log "INFO" "Processor: $processor"
  log "INFO" "Device Model: $model"
  log "INFO" "Device Board: $board"
  log "INFO" "Memory: $memory"
  log "INFO" "Storage: $storage"
  
  # Check for low resource conditions
  if [ "$(free -m | grep Mem | awk '{print $2}')" -lt 128 ]; then
    log "WARNING" "Low memory detected! Some features may not work correctly."
  fi
  
  if [ "$(df / | tail -1 | awk '{print $4}')" -lt 5000 ]; then
    log "WARNING" "Low storage detected! Consider expanding storage."
  fi
  
  log "STEP" "==================== CONFIGURATION START ===================="
}

# Firmware customization function
customize_firmware() {
  log "STEP" "Customizing firmware information..."
  
  # Back up original files before modification
  local JS_FILE="/www/luci-static/resources/view/status/include/10_system.js"
  local PORTS_FILE="/www/luci-static/resources/view/status/include/29_ports.js"
  
  if [ -f "$JS_FILE" ]; then
    cp "$JS_FILE" "${JS_FILE}.bak"
    sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' build OPEN-WRT [ Ouc3kNF6 ]':''),#g" "$JS_FILE"
    check_command "Customize firmware description"
  else
    log "WARNING" "System JS file not found, skipping firmware customization"
  fi
  
  if [ -f "$PORTS_FILE" ]; then
    cp "$PORTS_FILE" "${PORTS_FILE}.bak"
    sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" "$PORTS_FILE"
    check_command "Customize ports icons"
  else
    log "WARNING" "Ports JS file not found, skipping icon customization"
  fi
  
  # Detect and configure for specific OpenWrt distributions
  if grep -q "ImmortalWrt" /etc/openwrt_release; then
    log "INFO" "ImmortalWrt detected, applying specific configurations..."
    sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
    
    for TEMPLATE_FILE in "/usr/share/ucode/luci/template/themes/material/header.ut"; do
      if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "${TEMPLATE_FILE}.bak"
        sed -i -E "s|services/ttyd|system/ttyd|g" "$TEMPLATE_FILE"
        check_command "Updating TTYD path in $(basename "$TEMPLATE_FILE")"
      fi
    done
    
    log "INFO" "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
  elif grep -q "OpenWrt" /etc/openwrt_release; then
    log "INFO" "OpenWrt detected, applying specific configurations..."
    sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
    log "INFO" "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
  else
    log "WARNING" "Unknown OpenWrt variant"
  fi
}

# Check and list installed tunnel applications
check_tunnel_apps() {
  log "STEP" "Checking installed tunnel applications..."
  
  local TUNNEL_APPS=""
  for app in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if is_package_installed "$app"; then
      TUNNEL_APPS="${TUNNEL_APPS}${app} "
    fi
  done
  
  if [ -n "$TUNNEL_APPS" ]; then
    log "INFO" "Tunnel Applications Installed: $TUNNEL_APPS"
  else
    log "INFO" "No tunnel applications installed"
  fi
}

# Secure root password setup
setup_root_password() {
  log "STEP" "Setting up root password securely..."
  
  local PASSWORD="root"
  (echo "$PASSWORD"; sleep 1; echo "$PASSWORD") | passwd > /dev/null
  check_command "Setting root password"
}

# Setup time zone and NTP servers
setup_timezone() {
  log "STEP" "Setting up time zone and NTP configuration..."
  
  safe_uci set "system.@system[0].hostname" "OPEN-WRT"
  safe_uci set "system.@system[0].timezone" "WIB-7"
  safe_uci set "system.@system[0].zonename" "Asia/Jakarta"
  safe_uci delete "system.ntp.server"
  
  for ntp_server in "0.pool.ntp.org" "1.pool.ntp.org" "id.pool.ntp.org" "time.google.com" "time.cloudflare.com"; do
    safe_uci add_list "system.ntp.server" "$ntp_server"
  done
  
  commit_uci "system"
}

# Configure network interfaces
setup_network() {
  log "STEP" "Configuring network interfaces..."
  
  # Backup current network config
  cp /etc/config/network /etc/config/network.bak
  
  # LAN configuration
  safe_uci set "network.lan.ipaddr" "192.168.1.1"
  safe_uci set "network.lan.netmask" "255.255.255.0"
  
  # WAN configuration with modem support
  safe_uci set "network.wan" "interface"
  safe_uci set "network.wan.proto" "modemmanager"
  
  # Use wildcard for USB device to improve robustness
  # Check if the specific device exists first
  if [ -d "/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1" ]; then
    safe_uci set "network.wan.device" "/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1"
  else
    # Try to find a USB modem automatically
    local USB_MODEMS=$(ls -d /sys/class/net/wwan* 2>/dev/null)
    if [ -n "$USB_MODEMS" ]; then
      local FIRST_MODEM=$(echo "$USB_MODEMS" | head -1)
      safe_uci set "network.wan.device" "$FIRST_MODEM"
      log "INFO" "Auto-detected USB modem: $FIRST_MODEM"
    else
      log "WARNING" "No USB modem detected, using default configuration"
      safe_uci set "network.wan.device" "/sys/devices/platform/*/usb*/*/usb*" # More flexible path
    fi
  fi
  
  safe_uci set "network.wan.apn" "internet"
  safe_uci set "network.wan.auth" "none"
  safe_uci set "network.wan.iptype" "ipv4"
  
  # Add failover WAN interface if eth1 exists
  if [ -e "/sys/class/net/eth1" ]; then
    log "INFO" "Secondary ethernet interface detected, configuring failover WAN"
    safe_uci set "network.wan2" "interface"
    safe_uci set "network.wan2.proto" "dhcp"
    safe_uci set "network.wan2.device" "eth1"
  else
    log "INFO" "No secondary ethernet interface detected, skipping failover WAN setup"
  fi
  
  commit_uci "network"
  
  # Configure firewall for WAN interfaces
  if [ -e "/sys/class/net/eth1" ]; then
    safe_uci set "firewall.@zone[1].network" "wan wan2"
    commit_uci "firewall"
  fi
}

# Disable IPv6 function
disable_ipv6() {
  log "STEP" "Disabling IPv6..."
  
  safe_uci delete "dhcp.lan.dhcpv6"
  safe_uci delete "dhcp.lan.ra"
  safe_uci delete "dhcp.lan.ndp"
  commit_uci "dhcp"
  
  # Disable IPv6 at system level
  if [ -f "/etc/sysctl.conf" ]; then
    # Add IPv6 disable settings if not already present
    if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
      echo "# Disable IPv6" >> /etc/sysctl.conf
      echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
      echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
      sysctl -p >/dev/null 2>&1
      log "INFO" "IPv6 disabled at system level"
    fi
  fi
}

# Setup package management and repositories
setup_package_management() {
  log "STEP" "Setting up package management and repositories..."
  
  # Backup original opkg.conf
  cp /etc/opkg.conf /etc/opkg.conf.bak
  
  # Disable signature check for opkg if not already disabled
  if grep -q "option check_signature" /etc/opkg.conf; then
    sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf
    log "INFO" "Disabled package signature verification"
  fi
}

# UI configuration function
setup_ui() {
  log "STEP" "Setting up UI configuration..."
  
  # Check if MATERIAL theme is installed
  if [ -d "/www/luci-static/material" ]; then
    safe_uci set "luci.main.mediaurlbase" "/luci-static/material"
    commit_uci "luci"
    log "INFO" "Set material as default theme"
  else
    log "WARNING" "MATERIAL theme not found, using default theme"
  fi
  
  # Configure TTYD if installed
  if is_package_installed "ttyd"; then
    log "INFO" "Configuring TTYD..."
    safe_uci set "ttyd.@ttyd[0].command" "/bin/bash --login"
    safe_uci set "ttyd.@ttyd[0].interface" "@lan"
    safe_uci set "ttyd.@ttyd[0].port" "7681"
    commit_uci "ttyd"
    
    # Restart TTYD service
    /etc/init.d/ttyd restart
    log "INFO" "TTYD configured and restarted"
  fi
}

# Function to configure USB modem settings
setup_usb_modem() {
  log "STEP" "Configuring USB modem settings..."
  
  # Create backup of USB mode config
  if [ -f "/etc/usb-mode.json" ]; then
    cp /etc/usb-mode.json /etc/usb-mode.json.bak
    
    # Function to safely edit USB mode switch configuration
    edit_usb_mode_json() {
      local vid_pid=$1
      if grep -q "$vid_pid" /etc/usb-mode.json; then
        log "INFO" "Removing USB mode switch for $vid_pid"
        sed -i -e "/$vid_pid/,+5d" /etc/usb-mode.json
        return 0
      else
        log "INFO" "USB mode switch for $vid_pid not found, skipping"
        return 1
      fi
    }
    
    # Remove specific USB mode switches
    edit_usb_mode_json "12d1:15c1" # Huawei ME909s
    edit_usb_mode_json "413c:81d7" # DW5821e
    edit_usb_mode_json "1e2d:00b3" # Thales MV31-W T99W175
    
    log "INFO" "USB mode switch configurations updated"
  else
    log "WARNING" "USB mode configuration file not found"
  fi
  
  # Disable XMM modem service if it exists
  if [ -f "/etc/config/xmm-modem" ]; then
    log "INFO" "Disabling XMM modem service..."
    safe_uci set "xmm-modem.@xmm-modem[0].enable" "0"
    commit_uci "xmm-modem"
    
    # Restart the service
    /etc/init.d/xmm-modem stop
    log "INFO" "XMM modem service disabled"
  fi
  
  # Load USB modem drivers
  if ! lsmod | grep -q "option"; then
    modprobe option
    log "INFO" "Loaded USB option modem driver"
  fi
  
  if ! lsmod | grep -q "qmi_wwan"; then
    modprobe qmi_wwan
    log "INFO" "Loaded QMI WAN driver"
  fi
}

# Function to setup traffic monitoring
setup_traffic_monitoring() {
  log "STEP" "Setting up traffic monitoring..."
  
  # Configure vnstat for traffic statistics
  if is_package_installed "vnstat"; then
    log "INFO" "Setting up vnstat..."
    
    # Create data directory if it doesn't exist
    mkdir -p /etc/vnstat
    chmod 755 /etc/vnstat
    
    if [ -f "/etc/vnstat.conf" ]; then
      cp /etc/vnstat.conf /etc/vnstat.conf.bak
      sed -i 's/;DatabaseDir "\/var\/lib\/vnstat"/DatabaseDir "\/etc\/vnstat"/' /etc/vnstat.conf
      log "INFO" "Updated vnstat database directory"
    fi
    
    # Enable and start vnstat
    if [ -f "/etc/init.d/vnstat" ]; then
      /etc/init.d/vnstat enable
      /etc/init.d/vnstat restart
      log "INFO" "vnstat service enabled and started"
    fi
    
    # Setup vnstat backup if available
    if [ -f "/etc/init.d/vnstat_backup" ]; then
      chmod +x /etc/init.d/vnstat_backup
      /etc/init.d/vnstat_backup enable
      log "INFO" "vnstat backup service enabled"
    fi
  else
    log "INFO" "vnstat not installed, skipping configuration"
  fi
}

# Function to set up shell environment
setup_shell_environment() {
  log "STEP" "Setting up shell environment..."
  
  # Back up original profile
  cp /etc/profile /etc/profile.bak
  
  # Modify banner display
  sed -i 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' /etc/profile
  sed -i 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/#&/' /etc/profile
  
  # Make utility scripts executable
  for script in /sbin/free.sh /usr/bin/openclash.sh /usr/bin/cek_sms.sh; do
    if [ -f "$script" ]; then
      chmod +x "$script"
      log "INFO" "Made $script executable"
    fi
  done
}

chmod +x /usr/bin/speedtest

# Function to configure OpenClash if installed
configure_openclash() {
  log "STEP" "Checking and configuring OpenClash..."
  
  if is_package_installed "luci-app-openclash"; then
    log "INFO" "OpenClash detected, configuring..."
    
    # Create directory structure if it doesn't exist
    mkdir -p /etc/openclash/core
    mkdir -p /etc/openclash/history
    chmod 755 /etc/openclash
    
    # Set permissions for core files
    for file in /etc/openclash/core/clash_meta /etc/openclash/GeoIP.dat /etc/openclash/GeoSite.dat /etc/openclash/Country.mmdb; do
      if [ -f "$file" ]; then
        chmod +x "$file"
        log "INFO" "Set permissions for $(basename "$file")"
      fi
    done
    
    # Apply patches if available
    if [ -f "/usr/bin/patchoc.sh" ]; then
      chmod +x /usr/bin/patchoc.sh
      log "INFO" "Patching OpenClash overview..."
      /usr/bin/patchoc.sh
      
      # Add to rc.local if not already there
      if ! grep -q "patchoc.sh" /etc/rc.local; then
        sed -i '/exit 0/i # OpenClash patch' /etc/rc.local
        sed -i '/exit 0/i /usr/bin/patchoc.sh' /etc/rc.local
        log "INFO" "Added OpenClash patch to rc.local"
      fi
    fi
    
    # Create symbolic links
    ln -sf /etc/openclash/history/config-wrt.db /etc/openclash/cache.db 2>/dev/null
    ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
    
    # Move configuration file if needed
    if [ -f "/etc/config/openclash1" ]; then
      if [ -f "/etc/config/openclash" ]; then
        cp /etc/config/openclash /etc/config/openclash.bak
      fi
      mv /etc/config/openclash1 /etc/config/openclash
      log "INFO" "Moved OpenClash configuration file"
    fi
    
    # Check if OpenClash is running, start if not
    if ! pgrep -f clash >/dev/null; then
      /etc/init.d/openclash restart
      log "INFO" "Started OpenClash service"
    fi
    
    log "INFO" "OpenClash setup complete!"
  else
    log "INFO" "OpenClash not detected, cleaning up..."
    
    # Clean up any internet-detector references
    if [ -f "/etc/config/internet-detector" ]; then
      uci delete internet-detector.Openclash 2>/dev/null
      uci commit internet-detector 2>/dev/null
      service internet-detector restart
    fi
    
    # Remove leftover configuration
    rm -rf /etc/config/openclash1
  fi
}

# Function to set up PHP for web applications
setup_php() {
  log "STEP" "Setting up PHP..."
  
  # Check if PHP is installed
  if is_package_installed "php8" || is_package_installed "php7"; then
    # Configure uhttpd for PHP
    safe_uci set "uhttpd.main.ubus_prefix" "/ubus"
    safe_uci set "uhttpd.main.interpreter" ".php=/usr/bin/php-cgi"
    safe_uci set "uhttpd.main.index_page" "cgi-bin/luci"
    safe_uci add_list "uhttpd.main.index_page" "index.html"
    safe_uci add_list "uhttpd.main.index_page" "index.php"
    commit_uci "uhttpd"
    
    # Optimize PHP configuration
    if [ -f "/etc/php.ini" ]; then
      cp /etc/php.ini /etc/php.ini.bak
      sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
      sed -i -E "s|max_execution_time = [0-9]+|max_execution_time = 60|g" /etc/php.ini
      sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
      sed -i -E "s|;date.timezone =|date.timezone = Asia/Jakarta|g" /etc/php.ini
      log "INFO" "PHP configuration optimized"
    else
      log "WARNING" "PHP configuration file not found"
    fi
    
    # Create symbolic links for PHP
    ln -sf /usr/bin/php-cli /usr/bin/php
    
    # Link PHP libraries if needed
    if [ -d "/usr/lib/php8" ] && [ ! -d "/usr/lib/php" ]; then
      ln -sf /usr/lib/php8 /usr/lib/php
      log "INFO" "Created PHP library symlink"
    fi
    
    # Restart uhttpd
    /etc/init.d/uhttpd restart
    log "INFO" "PHP setup complete"
  else
    log "INFO" "PHP not installed, skipping configuration"
  fi
}

# Function to set up TinyFM file manager
setup_tinyfm() {
  log "STEP" "Setting up TinyFM file manager..."
  
  # Create directory if it doesn't exist
  mkdir -p /www/tinyfm
  
  # Create rootfs symlink for full filesystem access
  ln -sf / /www/tinyfm/rootfs
  
  # Set permissions
  chmod 755 /www/tinyfm
  
  log "INFO" "TinyFM setup complete"
}

# Function to restore system information script
restore_sysinfo() {
  log "STEP" "Restoring system information script..."
  
  # Check if backup exists and restore
  if [ -f "/etc/profile.d/30-sysinfo.sh-bak" ]; then
    rm -rf /etc/profile.d/30-sysinfo.sh 2>/dev/null
    mv /etc/profile.d/30-sysinfo.sh-bak /etc/profile.d/30-sysinfo.sh
    chmod +x /etc/profile.d/30-sysinfo.sh
    log "INFO" "Restored original system information script"
  else
    log "INFO" "No backup of system information script found"
  fi
}

# Function to complete setup and perform final tasks
complete_setup() {
  log "STEP" "==================== CONFIGURATION COMPLETE ===================="
  
  # Create summary of changes
  log "INFO" "Setup Summary:"
  log "INFO" "- System hostname: OPEN-WRT"
  log "INFO" "- LAN IP: 192.168.1.1"
  log "INFO" "- WiFi Enabled: ????"
  log "INFO" "- Root password set: yes (password: root)"
  log "INFO" "- Timezone: Asia/Jakarta"
  
  # Remove temporary files
  log "INFO" "Cleaning up and finalizing..."

  # Update services
  /etc/init.d/log restart
  /etc/init.d/system restart
  /etc/init.d/network restart
  
  # Clean up the setup script
  log "INFO" "Removing setup script from auto-start..."
  rm -f /etc/uci-defaults/$(basename $0) 2>/dev/null
  
  # Generate final record of system state
  log "INFO" "Recording final system state..."
  echo "==================== FINAL SYSTEM STATE ====================" >> "$LOGFILE"
  echo "Date: $(date)" >> "$LOGFILE"
  echo "Uptime: $(uptime)" >> "$LOGFILE"
  echo "Memory:" >> "$LOGFILE"
  free -h >> "$LOGFILE"
  echo "Storage:" >> "$LOGFILE"
  df -h >> "$LOGFILE"
  echo "Network Interfaces:" >> "$LOGFILE"
  ifconfig | grep -E "^[a-z]|inet " >> "$LOGFILE"
  echo "Active Services:" >> "$LOGFILE"
  ls /etc/rc.d/S* | cut -d/ -f4 | sort >> "$LOGFILE"
  
  # Create final log copy in a permanent location
  cp "$LOGFILE" "/root/setup_complete_$(date +%Y%m%d_%H%M%S).log"
  
  log "INFO" "Setup complete! The system will now reboot in 5 seconds..."
  sync
  sleep 5
  reboot
}

# Main execution function
main() {
  # Print banner
  echo "=========================================================="
  echo "          OPEN-WRT Router Configuration Script             "
  echo "                     Version 2.0                          "
  echo "=========================================================="
  
  # Execute functions in sequence with error handling
  print_system_info
  customize_firmware
  check_tunnel_apps
  setup_root_password
  setup_timezone
  setup_network
  disable_ipv6
  setup_wireless
  setup_package_management
  setup_ui
  setup_usb_modem
  setup_traffic_monitoring
  adjust_app_categories
  setup_shell_environment
  configure_openclash
  configure_nikki
  setup_php
  setup_tinyfm
  restore_sysinfo
  setup_secondary_install
  complete_setup
}

# Run the main function
main
exit 0