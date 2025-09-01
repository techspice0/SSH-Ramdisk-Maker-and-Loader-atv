#!/bin/bash

## SSH Ramdisk Maker (Apple TV Ready) - rewritten 2025
## Original: @Ralph0045 | Modified: @techspice0 + ChatGPT

echo "**** SSH Ramdisk_Maker 3.2 ****"

if [ $# -lt 2 ]; then
  echo "Usage:

  -d    specify device by model
  -i    specify iOS/tvOS version (optional; default is earliest available)

Example:
  ./Ramdisk_Maker.sh -d AppleTV3,1 -i 7.2
"
  exit 1
fi

# --- Parse args ---
args=("$@")
for i in {0..4}; do
  if [ "${args[i]}" = "-d" ]; then
    device=${args[i+1]}
  fi
  if [ "${args[i]}" = "-i" ]; then
    version=${args[i+1]}
  fi
done

# --- Apply AppleTV JSON mapping if available ---
if [ -f "./mappings.json" ] && command -v jq >/dev/null 2>&1; then
  apply_tvos_mapping() {
    local dev="$1"
    local ver="$2"
    local mapped

    # exact match
    mapped=$(jq -r --arg d "$dev" --arg v "$ver" '.devices[$d].mappings[$v] // empty' mappings.json)

    # major.minor fallback
    if [ -z "$mapped" ]; then
      majmin=$(echo "$ver" | awk -F. '{ if (NF>=2) print $1"."$2; else print $1 }')
      mapped=$(jq -r --arg d "$dev" --arg v "$majmin" '.devices[$d].mappings[$v] // empty' mappings.json)
    fi

    # major-only fallback
    if [ -z "$mapped" ]; then
      maj=$(echo "$ver" | awk -F. '{print $1}')
      mapped=$(jq -r --arg d "$dev" --arg v "$maj" '.devices[$d].mappings[$v] // empty' mappings.json)
    fi

    # return mapping only, log goes to stderr
    if [ -n "$mapped" ]; then
      echo "Mapped $dev reported version $ver -> tvOS $mapped" >&2
      echo "$mapped"
    else
      echo "$ver"
    fi
  }

  # Apply mapping, version variable will only contain version number
  version=$(apply_tvos_mapping "$device" "${version:-latest}")
fi

# --- Device architecture detection ---
is_64="false"

if [[ "$device" == AppleTV* ]]; then
    atv_num=$(echo "$device" | sed 's/AppleTV\([0-9]*\),.*/\1/')
    if [ "$atv_num" -ge 4 ]; then
        is_64="true"
    else
        is_64="false"
    fi
fi

# Dropbear key only required for 64-bit devices
if [ "$is_64" = "true" ] && [ ! -f "resources/dropbear_rsa_host_key" ]; then
  echo "dropbear_rsa_host_key missing. Generate one first."
  exit 1
fi

# --- Fetch IPSW link and BuildID ---
if [ -z "$version" ] || [ "$version" = "latest" ]; then
  ipsw_link=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/url")
  version=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.[0].version')
  BuildID=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.[0].buildid')
else
  ipsw_link=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/url")
  BuildID=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/info.json" | jq -r '.[0].buildid')
fi

echo "Device: $device"
echo "Version: $version"
echo "BuildID: $BuildID"
echo "IPSW: $ipsw_link"

# --- iOS major version ---
iOS_Vers=$(echo $version | awk -F. '{print $1}')

# --- RootFS key page ---
RootFS=$(curl -s "https://www.theiphonewiki.com/wiki/Firmware_Keys/${iOS_Vers}.x" | grep "$BuildID" | grep "$device" -m 1 | awk -F_ '{print $1}' | awk -F"wiki" '{print "wiki"$2}')

mkdir -p SSH-Ramdisk-$device/work
cd SSH-Ramdisk-$device/work || exit

echo "Downloading firmware keys..."
curl -s "https://www.theiphonewiki.com/${RootFS}_${BuildID}_(${device})" -o temp_keys.html

if [ -e "temp_keys.html" ]; then
  echo "Done!"
else
  echo "Failed to download firmware keys."
fi

# --- Continue with decryption and ramdisk building as before ---
# ... (rest of your script unchanged)

echo "Done!"# --- Extract firmware components ---
../../bin/partialZipBrowser -g BuildManifest.plist "$ipsw_link" &> /dev/null

images="iBSS.iBEC.applelogo.DeviceTree.kernelcache.RestoreRamDisk"

for i in {1..6}; do
    temp_type=$(echo "$images" | awk -v var=$i -F. '{print $var}' | awk '{print tolower($0)}')
    temp_type2=$(echo "$images" | awk -v var=$i -F. '{print $var}')

    # extract keys from temp_keys.html
    eval "$temp_type"_iv=$(grep "$temp_type-iv" temp_keys.html | awk -F"</code>" '{print $1}' | awk -F"-iv\">" '{print $2}')
    eval "$temp_type"_key=$(grep "$temp_type-key" temp_keys.html | awk -F"</code>" '{print $1}' | awk -F"$temp_type-key\">" '{print $2}')
    iv=${temp_type}_iv
    key=${temp_type}_key

    # find component in BuildManifest.plist
    if [ "$temp_type2" = "RestoreRamDisk" ]; then
        component=$(grep "$temp_type2" BuildManifest.plist -A100 | grep dmg -m1 | sed 's/<string>//' | sed 's/<\/string>//' | xargs)
    else
        component=$(grep "$temp_type2" BuildManifest.plist -A3000 | grep string -m1 | sed 's/<string>//' | sed 's/<\/string>//' | xargs)
    fi

    echo "Downloading $component..."
    ../../bin/partialZipBrowser -g "$component" "$ipsw_link" &> /dev/null
    echo "Done!"

    # decrypt based on architecture
    if [ "$is_64" = "true" ]; then
        if [ "$temp_type2" = "RestoreRamDisk" ]; then
            ../../bin/img4 -i "$component" -o RestoreRamDisk.raw.dmg ${!iv}${!key}
            # trustcache for iOS > 11
            if [ "$iOS_Vers" -gt 11 ]; then
                ../../bin/partialZipBrowser -g "Firmware/$component.trustcache" "$ipsw_link" &> /dev/null
            fi
        else
            ../../bin/img4 -i "$temp_type2*" -o "$temp_type2.raw" ${!iv}${!key}
        fi
    else
        if [ "$temp_type2" = "RestoreRamDisk" ]; then
            ../../bin/xpwntool "$component" RestoreRamDisk.dec.img3 -iv ${!iv} -k ${!key} -decrypt &> /dev/null
        else
            ../../bin/xpwntool "$temp_type2*" "$temp_type2.dec.img3" -iv ${!iv} -k ${!key} -decrypt &> /dev/null
        fi
    fi
done

echo "Making ramdisk..."

if [ "$is_64" = "true" ]; then
    # --- 64-bit AppleTV ramdisk ---
    ../../bin/tsschecker -d "$device" -e FFFFFFFFFFFFF -l -s
    plutil -extract ApImg4Ticket xml1 -o - *.shsh2 | xmllint -xpath '/plist/data/text()' - | base64 -D > apticket.der

    ../../bin/Kernel64Patcher kernelcache.raw kcache.patched -a
    python3 ../../bin/compareFiles.py kernelcache.raw kcache.patched

    if [ "$iOS_Vers" -gt 11 ]; then
        ../../bin/img4 -i *.trustcache -o trustcache -M apticket.der
        mv trustcache ../
    fi

    ../../bin/img4 -i kernelcache.re* -o kernelcache.img4 -T rkrn -P kc.bpatch -J -M apticket.der
    mv kernelcache.img4 ../

    ../../bin/kairos iBSS.raw iBSS.patched
    ../../bin/kairos iBEC.raw iBEC.patched -b "rd=md0 -v"

    ../../bin/img4 -i iBSS.patched -o iBSS.img4 -T ibss -A -M apticket.der
    ../../bin/img4 -i iBEC.patched -o iBEC.img4 -T ibec -A -M apticket.der
    mv -v iBSS.img4 ../
    mv -v iBEC.img4 ../

    ../../bin/img4 -i applelogo.raw -o applelogo.img4 -T logo -A -M apticket.der
    mv -v applelogo.img4 ../
    ../../bin/img4 -i DeviceTree.raw -o devicetree.img4 -T rdtr -A -M apticket.der
    mv -v devicetree.img4 ../

    # --- ramdisk ---
    hdiutil resize -size 100MB RestoreRamDisk.raw.dmg
    mkdir ramdisk_mountpoint
    hdiutil attach -mountpoint ramdisk_mountpoint RestoreRamDisk.raw.dmg
    tar -xvf ../../resources/iosbinpack.tar -C .
    cd iosbinpack64
    tar -cvf ../tar.tar bin sbin usr
    cd ..
    tar -xvf tar.tar -C ramdisk_mountpoint
    mkdir libs
    curl -LO https://www.dropbox.com/s/3mbep81xx8kmvak/dependencies.tar
    tar -xvf dependencies.tar -C libs
    cp -a libs/libncurses.5.4.dylib ramdisk_mountpoint/usr/lib
    cp -a ../../resources/dropbear.plist ramdisk_mountpoint/System/Library/LaunchDaemons
    cp -a ../../resources/dropbear_rsa_host_key ramdisk_mountpoint/private/var
    [ ! -e "ramdisk_mountpoint/usr/lib/libiconv.2.dylib" ] && cp -a libs/libiconv.2.dylib ramdisk_mountpoint/usr/lib
    ../../bin/ldid2 -S../../resources/dd_ent.plist ramdisk_mountpoint/bin/dd
    mkdir -p ramdisk_mountpoint/private/var/root
    hdiutil detach ramdisk_mountpoint
    ../../bin/img4 -i RestoreRamDisk.raw.dmg -o ramdisk.img4 -T rdsk -A -M apticket.der
    mv ramdisk.img4 ../
else
# --- 32-bit AppleTV ramdisk ---
../../bin/xpwntool RestoreRamDisk.dec.img3 RestoreRamDisk.raw.dmg
hdiutil resize -size 30MB RestoreRamDisk.raw.dmg
mkdir ramdisk_mountpoint
hdiutil attach -mountpoint ramdisk_mountpoint RestoreRamDisk.raw.dmg
tar -xvf ../../resources/ssh.tar -C ramdisk_mountpoint/
hdiutil detach ramdisk_mountpoint
../../bin/xpwntool RestoreRamDisk.raw.dmg ramdisk.dmg -t RestoreRamDisk.dec.img3
mv -v ramdisk.dmg ../

# iBSS
../../bin/xpwntool iBSS.dec.img3 iBSS.raw
../../bin/iBoot32Patcher iBSS.raw iBSS.patched -r
../../bin/xpwntool iBSS.patched iBSS -t iBSS.dec.img3
mv -v iBSS ../
# Keep the raw file for ramdisk / later use
cp -v iBSS.raw ../

# iBEC
../../bin/xpwntool iBEC.dec.img3 iBEC.raw
../../bin/iBoot32Patcher iBEC.raw iBEC.patched -r -d -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
../../bin/xpwntool iBEC.patched iBEC -t iBEC.dec.img3
mv -v iBEC ../
# Keep the raw file for ramdisk / later use
cp -v iBEC.raw ../

# Other components
mv -v applelogo.dec.img3 ../applelogo
mv -v DeviceTree.dec.img3 ../devicetree
mv -v kernelcache.dec.img3 ../kernelcache
fi

# --- Cleanup ---
cd ..
rm -rf work
cd ..

echo "SSH Ramdisk creation DONE!"
