#!/bin/bash

mkdir -p bin

# --- iBoot32Patcher ---
if [ -e "bin/iBoot32Patcher" ]; then
    echo "iBoot32Patcher is present"
else
    echo "Installing iBoot32Patcher..."
    git clone https://github.com/iH8sn0w/iBoot32Patcher
    cd iBoot32Patcher || exit
    clang iBoot32Patcher.c finders.c functions.c patchers.c -Wno-multichar -I. -o ../bin/iBoot32Patcher
    cd ..
    rm -rf iBoot32Patcher
fi

# --- xpwntool ---
if [ -e "bin/xpwntool" ]; then
    echo "xpwntool is present"
else
    echo "Installing xpwntool..."
    curl -LO https://dayt0n.github.io/odysseus/odysseus-0.999.zip
    unzip odysseus-0.999.zip -d odysseus
    cp odysseus/odysseus-0.999.0/macos/xpwntool bin/
    rm -rf odysseus odysseus-0.999.zip
fi

# --- Kernel64Patcher ---
if [ -e "bin/Kernel64Patcher" ]; then
    echo "Kernel64Patcher is present"
else
    echo "Installing Kernel64Patcher..."
    git clone https://github.com/Ralph0045/Kernel64Patcher.git
    cd Kernel64Patcher || exit
    gcc Kernel64Patcher.c -o Kernel64Patcher
    mv -v Kernel64Patcher ../bin
    cd ..
    rm -rf Kernel64Patcher
fi

# --- kairos ---
if [ -e "bin/kairos" ]; then
    echo "kairos is present"
else
    echo "Installing kairos..."
    git clone https://github.com/dayt0n/kairos.git
    cd kairos || exit
    make
    mv -v kairos ../bin
    cd ..
    rm -rf kairos
fi

# --- partialZipBrowser ---
if [ -e "bin/partialZipBrowser" ]; then
    echo "partialZipBrowser is present"
else
    echo "Installing partialZipBrowser..."
    curl -LO https://github.com/tihmstar/partialZipBrowser/releases/download/v1.0/partialZipBrowser.zip
    unzip partialZipBrowser.zip
    mv partialZipBrowser bin/
    rm -rf partialZipBrowser.zip
fi

# --- img4 ---
if [ -e "bin/img4" ]; then
    echo "img4lib is present"
else
    echo "Installing img4lib..."
    git clone --recursive https://github.com/xerub/img4lib.git
    cd img4lib || exit
    git submodule update --init --recursive
    make [CC="cross-cc"] [LD="cross-ld"] [CORECRYPTO=1] [COMMONCRYPTO=1]
    mv -v img4 ../bin
    cd ..
    rm -rf img4lib
fi

# --- ldid2 ---
if [ -e "bin/ldid2" ]; then
    echo "ldid2 is present"
else
    echo "Installing ldid2..."
    curl -LO https://github.com/xerub/ldid/releases/download/42/ldid.zip
    unzip ldid.zip -d ldid
    mv ldid/ldid2 bin/
    rm -rf ldid ldid.zip
fi

# --- tsschecker ---
if [ -e "bin/tsschecker" ]; then
    echo "tsschecker is present"
else
    echo "Installing tsschecker..."
    curl -LO https://github.com/tihmstar/tsschecker/releases/download/304/tsschecker_macOS_v304.zip
    unzip tsschecker_macOS_v304.zip -d tsschecker
    mv tsschecker/tsschecker bin/
    rm -rf tsschecker tsschecker_macOS_v304.zip
fi

# --- iosbinpack ---
if [ -e "resources/iosbinpack.tar" ]; then
    echo "iosbinpack is present"
else
    echo "Downloading iosbinpack..."
    git clone https://github.com/jakeajames/rootlessJB3.git
    mv -v rootlessJB3/rootlessJB/bootstrap/tars/iosbinpack.tar resources/
    rm -rf rootlessJB3
fi

# --- firmware.json ---
if [ -e "firmware.json" ]; then
    echo "firmware.json is present"
else
    echo "Downloading firmware.json..."
    curl https://api.ipsw.me/v2.1/firmwares.json --output firmware.json &> /dev/null
fi

# --- compareFiles.py ---
if [ -e "bin/compareFiles.py" ]; then
    echo "compareFiles.py is present"
else
    echo "Downloading compareFiles.py..."
    curl https://raw.githubusercontent.com/dualbootfun/dualbootfun.github.io/d947e2c9b6090a1e65a46ea6a58cd840986ff9d9/source/compareFiles.py --output bin/compareFiles.py
fi

# --- iproxy via Homebrew ---
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew first..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "Installing iproxy via brew..."
brew install libimobiledevice
# Copy iproxy binary to ./bin
IPROXY_PATH=$(brew --prefix)/bin/iproxy
if [ -f "$IPROXY_PATH" ]; then
    cp "$IPROXY_PATH" bin/
    echo "iproxy copied to ./bin"
else
    echo "Warning: iproxy not found in Homebrew path."
fi

echo "All requirements installed."
