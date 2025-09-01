#!/bin/bash

## SSH Ramdisk Maker (Apple TV Ready) - rewritten 2025
## Original: @Ralph0045 | Modified: @techspice0 + ChatGPT

echo "**** SSH Ramdisk_Maker 3.0 ****"

if [ $# -lt 2 ]; then
  echo "Usage:

  -d    specify device by model
  -i    specify iOS/tvOS version (optional; default is earliest available)

Example:
  ./ramdisk_maker.sh -d AppleTV3,1 -i 7.2
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

    # return mapping if found, else original
    if [ -n "$mapped" ]; then
      echo "Mapped $dev reported version $ver -> tvOS $mapped"
      echo "$mapped"
    else
      echo "$ver"
    fi
  }

  version=$(apply_tvos_mapping "$device" "${version:-latest}")
fi

# --- Device architecture detection ---
is_64="false"
type=$(echo ${device:0:6})

if [ "$type" = "iPhone" ]; then
  number=$(echo ${device:6} | awk -F, '{print $1}')
  if [ "$number" -gt 5 ]; then is_64="true"; fi
else
  type=$(echo ${device:0:4})
  number=$(echo ${device:4} | awk -F, '{print $1}')
  if [ "$type" = "iPad" ] && [ "$number" -gt 3 ]; then is_64="true"; fi
  if [ "$type" = "iPod" ] && [ "$number" -gt 5 ]; then is_64="true"; fi
  if [[ "$device" == AppleTV* ]] && [ "$number" -gt 2 ]; then is_64="true"; fi
fi

if [ "$is_64" = "true" ] && [ ! -f "resources/dropbear_rsa_host_key" ]; then
  echo "dropbear_rsa_host_key missing. Generate one first."
  exit 1
fi

# --- Fetch IPSW link and BuildID ---
if [ -z "$version" ] || [ "$version" = "latest" ]; then
  ipsw_link=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/url")
  version=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.version')
  BuildID=$(curl -s "https://api.ipsw.me/v2.1/$device/earliest/info.json" | jq -r '.buildid')
else
  ipsw_link=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/url")
  BuildID=$(curl -s "https://api.ipsw.me/v2.1/$device/$version/info.json" | jq -r '.buildid')
fi

echo "Device: $device"
echo "Version: $version"
echo "BuildID: $BuildID"
echo "IPSW: $ipsw_link"

# --- The rest of your original decryption/build logic ---
# (Download BuildManifest, firmware keys, decrypt components, patch iBSS/iBEC,
# build ramdisk, add dropbear, etc. — everything from your original script
# works as-is once $device/$version/$BuildID are correctly set.)


} &> /dev/null

iOS_Vers=`echo $version | awk -F. '{print $1}'`

{
## Define RootFS name

RootFS="$((curl "https://www.theiphonewiki.com/wiki/Firmware_Keys/$iOS_Vers.x") | grep "$BuildID"_"" |  grep $device -m 1| awk -F_ '{print $1}' | awk -F"wiki" '{print "wiki"$2}')"
} &> /dev/null

mkdir -p SSH-Ramdisk-$device/work
cd SSH-Ramdisk-$device/work

## Get wiki keys page

echo Downloadking firmware keys...

curl "https://www.theiphonewiki.com/$RootFS"_"$BuildID"_"($device)" --output temp_keys.html &> /dev/null

if [ -e "temp_keys.html" ]; then
echo Done!
else
echo Failed to download firmware keys
fi

# Get firmware keys, components and decrypt them

../../bin/partialZipBrowser -g BuildManifest.plist $ipsw_link &> /dev/null

images="iBSS.iBEC.applelogo.DeviceTree.kernelcache.RestoreRamDisk"

for i in {1..6}
 do
    temp_type="$((echo $images) | awk -v var=$i -F. '{print $var}' | awk '{print tolower($0)}')"
    temp_type2="$((echo $images) | awk -v var=$i -F. '{print $var}')"
    
    eval "$temp_type"_iv="$((cat temp_keys.html) | grep "$temp_type-iv" | awk -F"</code>" '{print $1}' | awk -F"-iv\"\>" '{print $2}')"
    eval "$temp_type"_key="$((cat temp_keys.html) | grep "$temp_type-key" | awk -F"</code>" '{print $1}' | awk -F"$temp_type-key\"\>" '{print $2}')"
    iv=$temp_type"_iv"
    key=$temp_type"_key"
    
    if [ "$temp_type2" = "RestoreRamDisk" ]; then
        component="$((cat BuildManifest.plist) | grep $boardcfg -A 3000 | grep $temp_type2 -A 100| grep dmg -m 1 | sed s+'<string>'++ | sed s+'</string>'++ | xargs)"
    else
        component="$((cat BuildManifest.plist) | grep $boardcfg -A 3000 | grep $temp_type2 | grep string -m 1 | sed s+'<string>'++ | sed s+'</string>'++ | xargs)"
    fi
    
    echo Downloading $component...
    
    ../../bin/partialZipBrowser -g $component $ipsw_link &> /dev/null
    
    echo Done!
    
    if [ "$is_64" = "true" ]; then
        if [ "$temp_type2" = "RestoreRamDisk" ]; then
            ../../bin/img4 -i $component -o RestoreRamDisk.raw.dmg ${!iv}${!key}
            if [ "$iOS_Vers" -gt "11" ]; then
                echo Downloading $component.trustcache...
                ../../bin/partialZipBrowser -g Firmware/$component.trustcache $ipsw_link &> /dev/null
                echo Done!
            fi
        else
            ../../bin/img4 -i $temp_type2* -o $temp_type2.raw ${!iv}${!key}
        fi
    else
    
        if [ "$temp_type2" = "RestoreRamDisk" ]; then
            ../../bin/xpwntool $component RestoreRamDisk.dec.img3 -iv ${!iv} -k ${!key} -decrypt &> /dev/null
        else
            ../../bin/xpwntool $temp_type2* $temp_type2.dec.img3 -iv ${!iv} -k ${!key} -decrypt &> /dev/null
        fi
    fi
done

echo Making ramdisk...

{
if [ "$is_64" = "true" ]; then
    ../../bin/tsschecker -d $device -e FFFFFFFFFFFFF -l -s
    plutil -extract ApImg4Ticket xml1 -o - *.shsh2 | xmllint -xpath '/plist/data/text()' - | base64 -D > apticket.der
    ../../bin/Kernel64Patcher kernelcache.raw kcache.patched -a
    python3 ../../bin/compareFiles.py kernelcache.raw kcache.patched
    if [ "$iOS_Vers" -gt "11" ]; then
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
    hdiutil resize -size 100MB RestoreRamDisk.raw.dmg
    mkdir ramdisk_mountpoint
    hdiutil attach -mountpoint ramdisk_mountpoint/ RestoreRamDisk.raw.dmg
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
    
    if [ -e "ramdisk_mountpoint/usr/lib/libiconv.2.dylib" ]; then
    echo ""
    else
    cp -a libs/libiconv.2.dylib ramdisk_mountpoint/usr/lib
    fi
    ../../bin/ldid2 -S../../resources/dd_ent.plist ramdisk_mountpoint/bin/dd
    mkdir ramdisk_mountpoint/private/var/root
    hdiutil detach ramdisk_mountpoint
    ../../bin/img4 -i RestoreRamDisk.raw.dmg -o ramdisk.img4 -T rdsk -A -M apticket.der
    mv ramdisk.img4 ../
    cd ..
    rm -rf work
    cd ..
else
    ../../bin/xpwntool RestoreRamDisk.dec.img3 RestoreRamDisk.raw.dmg
    hdiutil resize -size 30MB RestoreRamDisk.raw.dmg
    mkdir ramdisk_mountpoint
    hdiutil attach -mountpoint ramdisk_mountpoint/ RestoreRamDisk.raw.dmg
    tar -xvf ../../resources/ssh.tar -C ramdisk_mountpoint/
    hdiutil detach ramdisk_mountpoint
    ../../bin/xpwntool RestoreRamDisk.raw.dmg ramdisk.dmg -t RestoreRamDisk.dec.img3
    mv -v ramdisk.dmg ../
    ../../bin/xpwntool iBSS.dec.img3 iBSS.raw
    ../../bin/iBoot32Patcher iBSS.raw iBSS.patched -r
    ../../bin/xpwntool iBSS.patched iBSS -t iBSS.dec.img3
    mv -v iBSS ../
    ../../bin/xpwntool iBEC.dec.img3 iBEC.raw
    ../../bin/iBoot32Patcher iBEC.raw iBEC.patched -r -d -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
    ../../bin/xpwntool iBEC.patched iBEC -t iBEC.dec.img3
    mv -v iBEC ../
    mv -v applelogo.dec.img3 ../applelogo
    mv -v DeviceTree.dec.img3 ../devicetree
    mv -v kernelcache.dec.img3 ../kernelcache
    cd ..
    rm -rf work
    cd ..
fi

} &> /dev/null

echo Done!
