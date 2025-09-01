#!/bin/bash

## SSH Ramdisk Maker (Apple TV 3,1 Ready) - 2025
## Original: @Ralph0045 | Modified: @techspice0 + ChatGPT

echo "**** SSH Ramdisk_Maker 3.3 - AppleTV3,1 Fix ****"

if [ $# -lt 2 ]; then
  echo "Usage:

  -d    specify device (e.g., AppleTV3,1)
  -i    specify tvOS version (optional)

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

# --- Apply mapping if available ---
if [ -f "./mappings.json" ] && command -v jq >/dev/null 2>&1; then
  apply_tvos_mapping() {
    local dev="$1"
    local ver="$2"
    local mapped

    mapped=$(jq -r --arg d "$dev" --arg v "$ver" '.devices[$d].mappings[$v] // empty' mappings.json)
    if [ -z "$mapped" ]; then
      majmin=$(echo "$ver" | awk -F. '{if(NF>=2) print $1"."$2; else print $1}')
      mapped=$(jq -r --arg d "$dev" --arg v "$majmin" '.devices[$d].mappings[$v] // empty' mappings.json)
    fi
    if [ -z "$mapped" ]; then
      maj=$(echo "$ver" | awk -F. '{print $1}')
      mapped=$(jq -r --arg d "$dev" --arg v "$maj" '.devices[$d].mappings[$v] // empty' mappings.json)
    fi

    if [ -n "$mapped" ]; then
      echo "Mapped $dev reported version $ver -> tvOS $mapped" >&2
      echo "$mapped"
    else
      echo "$ver"
    fi
  }

  version=$(apply_tvos_mapping "$device" "${version:-latest}")
fi

# --- 32-bit AppleTV check ---
if [[ "$device" == AppleTV3,1 ]]; then
    is_64="false"
else
    echo "This script currently supports only AppleTV3,1 (32-bit)."
    exit 1
fi

# --- Fetch IPSW and BuildID ---
ipsw_link=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/url")
BuildID=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/info.json" | jq -r '.[0].buildid')

echo "Device: $device"
echo "Version: $version"
echo "BuildID: $BuildID"
echo "IPSW: $ipsw_link"

# --- Prepare working directory ---
mkdir -p SSH-Ramdisk-$device/work
cd SSH-Ramdisk-$device/work || exit

# --- Download firmware keys ---
iOS_Vers=$(echo $version | awk -F. '{print $1}')
RootFS=$(curl -s "https://www.theiphonewiki.com/wiki/Firmware_Keys/${iOS_Vers}.x" | grep "$BuildID" | grep "$device" -m1 | awk -F_ '{print $1}' | awk -F"wiki" '{print "wiki"$2}')
curl -s "https://www.theiphonewiki.com/${RootFS}_${BuildID}_(${device})" -o temp_keys.html

if [ ! -e temp_keys.html ]; then
  echo "Failed to download firmware keys."
  exit 1
fi

# --- Extract BuildManifest ---
../../bin/partialZipBrowser -g BuildManifest.plist "$ipsw_link" &> /dev/null

# --- Components ---
components="iBSS.iBEC.applelogo.DeviceTree.kernelcache.RestoreRamDisk"

for comp in ${components//./ }; do
    # Get component filename
    file=$(grep "$comp" BuildManifest.plist -A3000 | grep -m1 string | sed 's/<string>//' | sed 's/<\/string>//' | xargs)
    echo "Downloading $file..."
    ../../bin/partialZipBrowser -g "$file" "$ipsw_link" &> /dev/null
    echo "Done!"

    # Get IV/KEY
    iv=$(grep -i "${file}-iv" temp_keys.html | awk -F": " '{print $2}' | tr -d '\r\n')
    key=$(grep -i "${file}-key" temp_keys.html | awk -F": " '{print $2}' | tr -d '\r\n')

    if [ -z "$iv" ] || [ -z "$key" ]; then
        echo "Error: missing IV/key for $file"
        exit 1
    fi

    # Decrypt
    if [ "$comp" = "RestoreRamDisk" ]; then
        ../../bin/xpwntool "$file" RestoreRamDisk.dec.img3 -iv $iv -k $key -decrypt
    else
        ../../bin/xpwntool "$file" "$comp.dec.img3" -iv $iv -k $key -decrypt
    fi
done

# --- Build ramdisk ---
../../bin/xpwntool RestoreRamDisk.dec.img3 RestoreRamDisk.raw.dmg
hdiutil resize -size 30MB RestoreRamDisk.raw.dmg
mkdir ramdisk_mountpoint
hdiutil attach -mountpoint ramdisk_mountpoint RestoreRamDisk.raw.dmg
tar -xvf ../../resources/ssh.tar -C ramdisk_mountpoint/
hdiutil detach ramdisk_mountpoint
../../bin/xpwntool RestoreRamDisk.raw.dmg ramdisk.dmg -t RestoreRamDisk.dec.img3

# --- Keep raw iBSS / iBEC ---
cp -v iBSS.dec.img3 ../iBSS.raw
cp -v iBEC.dec.img3 ../iBEC.raw

# --- Move other components ---
mv -v applelogo.dec.img3 ../applelogo
mv -v DeviceTree.dec.img3 ../devicetree
mv -v kernelcache.dec.img3 ../kernelcache

# --- Cleanup ---
cd ..
rm -rf work
cd ..

echo "SSH Ramdisk creation DONE!"
