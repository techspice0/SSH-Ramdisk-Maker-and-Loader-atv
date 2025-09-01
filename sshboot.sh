#!/bin/bash

# SSH Ramdisk Booter for Apple TV
# Uses iBSS/iBEC and ramdisk created by mksshrd.sh
# Requirements: bin/iproxy, bin/iBoot32Patcher, bin/xpwntool, bin/kairos, etc.

set -e

DEVICE_IP="127.0.0.1"
SSH_PORT=2222

usage() {
    echo "Usage: $0 -d <device_model> [-r <ramdisk_dir>] [-p <ssh_port>]"
    echo "  -d   Device model (e.g., AppleTV3,1)"
    echo "  -r   Path to SSH Ramdisk directory (default: SSH-Ramdisk-<device>)"
    echo "  -p   Local SSH port for port forwarding (default: 2222)"
    exit 1
}

while getopts "d:r:p:" opt; do
    case $opt in
        d) DEVICE=$OPTARG ;;
        r) RAMDISK_DIR=$OPTARG ;;
        p) SSH_PORT=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$DEVICE" ]; then
    usage
fi

RAMDISK_DIR=${RAMDISK_DIR:-SSH-Ramdisk-$DEVICE}

# Check files
for file in "$RAMDISK_DIR/iBSS.patched" "$RAMDISK_DIR/iBEC.patched" "$RAMDISK_DIR/ramdisk.dmg"; do
    if [ ! -f "$file" ]; then
        echo "Missing $file, run mksshrd.sh first"
        exit 1
    fi
done

echo "Booting SSH Ramdisk for $DEVICE..."

# Step 1: Upload and boot iBSS
echo "Booting iBSS..."
bin/kairos "$RAMDISK_DIR/iBSS.patched"

# Step 2: Boot iBEC with ramdisk
echo "Booting iBEC with ramdisk..."
bin/kairos "$RAMDISK_DIR/iBEC.patched" -b "rd=md0 -v"

# Step 3: Start iproxy for SSH
echo "Starting iproxy for SSH on localhost:$SSH_PORT..."
bin/iproxy "$SSH_PORT" 22 &

echo "SSH Ramdisk booted. Connect with:"
echo "ssh root@127.0.0.1 -p $SSH_PORT"
