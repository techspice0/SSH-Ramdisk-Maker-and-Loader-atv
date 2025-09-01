#!/bin/bash

CONFIG_FILE="config.cfg"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found! Run gencfg.sh first."
  exit 1
fi

# --- Load config ---
source "$CONFIG_FILE"

echo "**** SSH Ramdisk Builder ****"
echo "Device: $DEVICE"
echo "IPSW version: $IPSW_VER"
echo "64-bit: $IS_64"
echo "Key page URL: $KEYPAGE_URL"
echo "IPSW URL: $IPSW_URL"

# --- Download IPSW info ---
echo "Fetching BuildID and other info..."
BUILDID=$(curl -s "$IPSW_URL" | jq -r '.[0].buildid')

echo "BuildID: $BUILDID"

# --- Download firmware keys ---
mkdir -p work
cd work || exit

echo "Downloading firmware keys..."
curl -s "${KEYPAGE_URL}/${BUILDID}_(${DEVICE})" -o temp_keys.html

if [ ! -f temp_keys.html ]; then
  echo "Failed to download firmware keys!"
  exit 1
fi
echo "Firmware keys downloaded."

# --- Placeholder: extraction and decryption ---
echo "Now you would decrypt iBSS/iBEC/RestoreRamDisk/kernelcache using your binaries..."

# --- Placeholder: SSH ramdisk creation ---
echo "Build ramdisk and inject SSH binaries here..."
echo "(Use ssh.tar, dropbear keys, etc.)"

cd ..
echo "SSH Ramdisk creation DONE!"
