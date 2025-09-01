#!/bin/bash

CONFIG_FILE="sshrd_config.json"

echo "**** SSH Ramdisk Config Generator ****"

read -p "Device (e.g., AppleTV3,1): " device
read -p "iOS/tvOS version (leave blank for earliest): " version
read -p "64-bit device? (y/n): " is64
read -p "IPSWHOST URL (leave blank for default via ipsw.me API): " ipsw_url
read -p "AppleWiki rootFS key page (leave blank for default): " applewiki_url

if [[ "$is64" =~ ^[Yy]$ ]]; then
    is64=true
else
    is64=false
fi

# fetch IPSW URL if blank
if [ -z "$ipsw_url" ]; then
    if [ -z "$version" ]; then
        ipsw_url=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/url")
        version=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.[0].version')
        buildid=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.[0].buildid')
    else
        ipsw_url=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/url")
        buildid=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/info.json" | jq -r '.[0].buildid')
    fi
else
    buildid=""  # optional, user can fill manually
fi

# AppleWiki URL fallback
if [ -z "$applewiki_url" ]; then
    applewiki_url="https://www.theiphonewiki.com/wiki/Firmware_Keys/${version%%.*}.x"
fi

mkdir -p config
cat > config/$CONFIG_FILE <<EOF
{
  "device": "$device",
  "version": "$version",
  "is64": $is64,
  "ipsw_url": "$ipsw_url",
  "buildid": "$buildid",
  "applewiki_url": "$applewiki_url"
}
EOF

echo "Configuration saved to config/$CONFIG_FILE"
