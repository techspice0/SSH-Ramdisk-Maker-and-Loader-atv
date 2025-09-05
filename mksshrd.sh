#!/usr/bin/env bash
# mksshrd.sh
# Build SSH Ramdisk from JSON config (32-bit and 64-bit Apple TVs/iOS devices)

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <config.json>"
    exit 1
fi

CONFIG="$1"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$SCRIPT_DIR/bin"
WORKDIR="$SCRIPT_DIR/work"
OUTDIR="$SCRIPT_DIR/SSH-Ramdisk-$(jq -r '.device' "$CONFIG")"

mkdir -p "$WORKDIR" "$OUTDIR"
cd "$WORKDIR"

# Parse JSON config
DEVICE=$(jq -r '.device' "$CONFIG")
IS64=$(jq -r '.is64' "$CONFIG")
IPSW_URL=$(jq -r '.ipsw_url' "$CONFIG")

echo "[*] Device: $DEVICE"
echo "[*] 64-bit? $IS64"
echo "[*] IPSW URL: $IPSW_URL"

COMPONENTS=(iBSS iBEC DeviceTree KernelCache RestoreRamDisk)
declare -A IV KEY PATH

for comp in "${COMPONENTS[@]}"; do
    IV[$comp]=$(jq -r ".keys[\"$comp\"].iv" "$CONFIG")
    KEY[$comp]=$(jq -r ".keys[\"$comp\"].key" "$CONFIG")
    PATH[$comp]=$(jq -r ".components[\"$comp\"]" "$CONFIG")
done

# Download & decrypt components
for comp in "${COMPONENTS[@]}"; do
    echo "[*] Processing $comp..."
    FILE="${PATH[$comp]}"
    BASENAME=$(basename "$FILE")

    # Download if missing
    if [ ! -f "$BASENAME" ]; then
        echo "[+] Downloading $FILE..."
        "$BIN_DIR/partialZipBrowser" -g "$BASENAME" "$IPSW_URL" || {
            echo "[!] Failed to download $BASENAME"
            exit 1
        }
    fi

    # Decrypt based on 32/64-bit
    if [ "$IS64" = "true" ]; then
        if [ "$comp" = "RestoreRamDisk" ]; then
            "$BIN_DIR/img4" -i "$BASENAME" -o RestoreRamDisk.raw.dmg -k "${KEY[$comp]}" -iv "${IV[$comp]}"
        else
            "$BIN_DIR/img4" -i "$BASENAME" -o "${comp}.raw" -k "${KEY[$comp]}" -iv "${IV[$comp]}"
        fi
    else
        if [ "$comp" = "RestoreRamDisk" ]; then
            "$BIN_DIR/xpwntool" "$BASENAME" RestoreRamDisk.raw.dmg -k "${KEY[$comp]}" -iv "${IV[$comp]}" -decrypt
        else
            "$BIN_DIR/xpwntool" "$BASENAME" "${comp}.raw" -k "${KEY[$comp]}" -iv "${IV[$comp]}" -decrypt
        fi
    fi
done

# Build SSH ramdisk
echo "[*] Creating SSH ramdisk..."
mkdir -p ramdisk_mount

if [ "$IS64" = "true" ]; then
    # 64-bit: img4/64-bit style mount
    hdiutil attach -mountpoint ramdisk_mount RestoreRamDisk.raw.dmg
    tar -xvf "$SCRIPT_DIR/resources/iosbinpack.tar" -C ramdisk_mount
    cp "$SCRIPT_DIR/resources/dropbear.plist" ramdisk_mount/System/Library/LaunchDaemons/
    cp "$SCRIPT_DIR/resources/dropbear_rsa_host_key" ramdisk_mount/private/var/
else
    # 32-bit: xpwntool style mount
    hdiutil attach -mountpoint ramdisk_mount RestoreRamDisk.raw.dmg
    tar -xvf "$SCRIPT_DIR/resources/ssh.tar" -C ramdisk_mount
fi

hdiutil detach ramdisk_mount

# Repack RestoreRamDisk for final output
if [ "$IS64" = "true" ]; then
    "$BIN_DIR/img4" -i RestoreRamDisk.raw.dmg -o "$OUTDIR/ramdisk.dmg"
else
    "$BIN_DIR/xpwntool" RestoreRamDisk.raw.dmg "$OUTDIR/ramdisk.dmg" -t RestoreRamDisk.raw.dmg
fi

# Copy other components
for comp in "${COMPONENTS[@]}"; do
    if [ "$comp" != "RestoreRamDisk" ]; then
        cp -v "${comp}.raw" "$OUTDIR/$comp.raw"
    fi
done

echo "[+] SSH Ramdisk successfully built at $OUTDIR"
