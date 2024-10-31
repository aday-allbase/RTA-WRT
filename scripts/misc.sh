#!/bin/bash

echo "Start Downloading Misc files and setup configuration!"
echo "Current Path: $PWD"

#setup custom setting for openwrt and immortalwrt
sed -i "s/Ouc3kNF6/$DATE/g" files/etc/uci-defaults/99-init-settings.sh
echo "$BASE"
sed -i '/# setup misc settings/ a\mv \/www\/luci-static\/resources\/view\/status\/include\/29_temp.js \/www\/luci-static\/resources\/view\/status\/include\/17_temp.js' files/etc/uci-defaults/99-init-settings.sh

if [ "$TARGET" == "Raspberry Pi 4B" ]; then
    echo "$TARGET"
elif [ "$TARGET" == "x86-64" ]; then
    rm packages/luci-app-oled_1.0_all.ipk
else
    rm packages/luci-app-oled_1.0_all.ipk
fi

if [ "$TYPE" == "AMLOGIC" ]; then
    sed -i -E "s|nullwrt|amlogic|g" files/etc/uci-defaults/99-init-settings.sh
fi

echo "All custom configuration setup completed!"
