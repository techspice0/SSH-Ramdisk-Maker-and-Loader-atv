#!/bin/bash

CONFIG_FILE="config/sshrd_config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found! Run gencfg.sh first."
    exit 1
fi

# read config
device=$(jq -r '.device' $CONFIG_FILE)
version=$(jq -r '.version' $CONFIG_FILE)
is64=$(jq -r '.is64' $CONFIG_FILE)
ipsw_url=$(jq -r '.ipsw_url' $CONFIG_FILE)
buildid=$(jq -r '.buildid' $CONFIG_FILE)
applewiki_url=$(jq -r '.applewiki_url' $CONFIG_FILE)

echo "**** Building SSH Ramdisk ****"
echo "Device: $device, Version: $version, 64-bit: $is64"
echo "IPSW URL: $ipsw_url"
echo "AppleWiki URL: $applewiki_url"

mkdir -p SSH-Ramdisk-$device/work
cd SSH-Ramdisk-$device/work || exit

# Download IPSW components using partialZipBrowser
echo "Extracting BuildManifest.plist..."
../../bin/partialZipBrowser -g BuildManifest.plist "$ipsw_url" &> /dev/null

components="iBSS iBEC applelogo DeviceTree kernelcache RestoreRamDisk"

for comp in $components; do
    echo "Processing $comp..."
    # fetch keys from AppleWiki page
    iv=$(grep "$comp-iv" ../../temp_keys.html | awk -F">" '{print $2}' | awk -F"<" '{print $1}')
    key=$(grep "$comp-key" ../../temp_keys.html | awk -F">" '{print $2}' | awk -F"<" '{print $1}')

    ../../bin/partialZipBrowser -g "$comp*" "$ipsw_url" &> /dev/null

    if [ "$comp" = "RestoreRamDisk" ]; then
        if [ "$is64" = "true" ]; then
            ../../bin/img4 -i "$comp*" -o RestoreRamDisk.raw.dmg -iv $iv -k $key
        else
            ../../bin/xpwntool "$comp*" RestoreRamDisk.dec.img3 -iv $iv -k $key -decrypt
        fi
    else
        if [ "$is64" = "true" ]; then
            ../../bin/img4 -i "$comp*" -o "$comp.raw" -iv $iv -k $key
        else
            ../../bin/xpwntool "$comp*" "$comp.dec.img3" -iv $iv -k $key -decrypt
        fi
    fi
done

# Ramdisk build (basic)
if [ "$is64" = "true" ]; then
    echo "64-bit ramdisk build not implemented yet (placeholder)"
else
    echo "Building 32-bit ramdisk..."
    ../../bin/xpwntool RestoreRamDisk.dec.img3 RestoreRamDisk.raw.dmg
    hdiutil resize -size 30MB RestoreRamDisk.raw.dmg
    mkdir ramdisk_mountpoint
    hdiutil attach -mountpoint ramdisk_mountpoint RestoreRamDisk.raw.dmg
    tar -xvf ../../resources/ssh.tar -C ramdisk_mountpoint/
    hdiutil detach ramdisk_mountpoint
    ../../bin/xpwntool RestoreRamDisk.raw.dmg ramdisk.dmg -t RestoreRamDisk.dec.img3
    mv ramdisk.dmg ../
fi

cd ../..
echo "SSH Ramdisk creation DONE!"
