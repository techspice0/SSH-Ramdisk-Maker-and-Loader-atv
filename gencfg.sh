#!/usr/bin/env bash
# genconfig.sh
# Auto-generate config JSON for SSH Ramdisk project (macOS compatible)
# Usage:
#   ./genconfig.sh <device> <core_ios> <keyver>
# or:
#   ./genconfig.sh   # will ask interactively

set -euo pipefail

# ---------- Input ----------
if [ $# -eq 3 ]; then
    DEVICE="$1"
    CORE_IOS="$2"
    KEYVER="$3"
else
    read -rp "Enter device (e.g. AppleTV3,1): " DEVICE
    read -rp "Enter core iOS version (e.g. 8.3 for tvOS 7.2): " CORE_IOS
    read -rp "Enter key version (e.g. 7.2): " KEYVER
fi

echo "[*] Device   : $DEVICE"
echo "[*] Core iOS : $CORE_IOS"
echo "[*] Key ver  : $KEYVER"

# ---------- Settings ----------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PZB_BIN="$SCRIPT_DIR/bin/partialZipBrowser"
OUTDIR="$SCRIPT_DIR/config"
WORKDIR="$SCRIPT_DIR/work"
USER_AGENT="ssh-ramdisk-gencfg/1.0"

mkdir -p "$OUTDIR" "$WORKDIR"
cd "$WORKDIR"

# ---------- Get IPSW URL ----------
echo "[*] Querying ipsw.me..."
IPSW_URL=$(curl -s "https://api.ipsw.me/v2.1/$DEVICE/$CORE_IOS/url")

if [ -z "$IPSW_URL" ]; then
    echo "[!] Failed to get IPSW URL from ipsw.me"
    exit 1
fi
echo "[+] IPSW URL: $IPSW_URL"

# ---------- Fetch BuildManifest ----------
echo "[*] Fetching BuildManifest..."
$PZB_BIN -g BuildManifest.plist "$IPSW_URL" >/dev/null || {
    echo "[!] Failed to fetch BuildManifest"
    exit 1
}
echo "[+] BuildManifest saved."

# ---------- Firmware Keys ----------
MAJOR_VER="${KEYVER%%.*}"
MAJOR_KEYS_URL="https://www.theiphonewiki.com/wiki/Firmware_Keys/${MAJOR_VER}.x"

echo "[*] Fetching major firmware keys page..."
curl -s -A "$USER_AGENT" "$MAJOR_KEYS_URL" -o temp_keys_major.html || true

# ---------- Device-specific subpage ----------
SUBPAGE=$(grep -Ei "href=\"/wiki/.*\($DEVICE\)\"" temp_keys_major.html \
         | grep -i "$KEYVER" \
         | head -1 \
         | sed -E 's/.*href="([^"]+)".*/\1/')

# Fallback if exact version not found
if [ -z "$SUBPAGE" ]; then
    echo "[*] Exact version not found, falling back to first device match..."
    SUBPAGE=$(grep -Ei "href=\"/wiki/.*\($DEVICE\)\"" temp_keys_major.html \
             | head -1 \
             | sed -E 's/.*href="([^"]+)".*/\1/')
fi

if [ -z "$SUBPAGE" ]; then
    echo "[!] Could not find wiki subpage for $DEVICE $KEYVER"
    exit 1
fi

FULL_URL="https://www.theiphonewiki.com$SUBPAGE"
echo "[*] Downloading device-specific firmware keys page..."
curl -s -A "$USER_AGENT" "$FULL_URL" -o temp_keys.html || true

if ! grep -q "key" temp_keys.html; then
    echo "[!] Could not fetch firmware keys from device page"
    exit 1
fi
echo "[+] Keys page saved."

# ---------- Components ----------
COMP_LIST=(iBSS iBEC DeviceTree AppleLogo KernelCache LLB RecoveryMode RestoreRamDisk)
COMP_IV=()
COMP_KEY=()
COMP_PATH=()

for i in "${!COMP_LIST[@]}"; do
    comp="${COMP_LIST[$i]}"
    lc=$(echo "$comp" | tr 'A-Z' 'a-z')

    # Fetch IV/key
    iv=$(grep -i "${lc}-iv" temp_keys.html | head -1 | sed -E 's/.*-iv[^>]*>([0-9a-fA-F]+).*/\1/')
    key=$(grep -i "${lc}-key" temp_keys.html | head -1 | sed -E 's/.*-key[^>]*>([0-9a-fA-F]+).*/\1/')
    COMP_IV[$i]="$iv"
    COMP_KEY[$i]="$key"

    # Fetch BuildManifest path
    if [ "$comp" = "RestoreRamDisk" ]; then
        path=$(grep -A100 -i "$comp" BuildManifest.plist | grep dmg -m1 | sed -E 's/.*<string>([^<]+)<\/string>.*/\1/')
    else
        path=$(grep -A20 -i "$comp" BuildManifest.plist | grep -m1 "<string>" | sed -E 's/.*<string>([^<]+)<\/string>.*/\1/')
    fi
    COMP_PATH[$i]="$path"
done

# ---------- Write JSON ----------
OUTFILE="$OUTDIR/${DEVICE}_${KEYVER}.json"
{
echo "{"
echo "  \"device\": \"$DEVICE\","
echo "  \"is64\": false,"
echo "  \"keyver\": \"$KEYVER\","
echo "  \"core_ios\": \"$CORE_IOS\","
echo "  \"ipsw_url\": \"$IPSW_URL\","
echo "  \"components\": {"
for i in "${!COMP_LIST[@]}"; do
    comp="${COMP_LIST[$i]}"
    path="${COMP_PATH[$i]}"
    printf '    "%s": "%s"' "$comp" "$path"
    [ "$i" -lt $((${#COMP_LIST[@]}-1)) ] && echo "," || echo
done
echo "  },"
echo "  \"keys\": {"
for i in "${!COMP_LIST[@]}"; do
    comp="${COMP_LIST[$i]}"
    iv="${COMP_IV[$i]}"
    key="${COMP_KEY[$i]}"
    printf '    "%s": { "iv": "%s", "key": "%s" }' "$comp" "$iv" "$key"
    [ "$i" -lt $((${#COMP_LIST[@]}-1)) ] && echo "," || echo
done
echo "  }"
echo "}"
} > "$OUTFILE"

echo "[+] Config written to $OUTFILE"
