#!/bin/bash

set -e

build_udev_hack() {
    # See https://bugs.launchpad.net/ubuntu/+source/cryptsetup/+bug/1589083
    gcc -shared -fPIC -o no-udev.so UdevDisableLib.c -ldl
}

build_chooser() {
    sudo apt install libncursesw5-dev libncurses5-dev
    go get github.com/rthornton128/goncurses
    (cd chooser &&
     go build chooser.go
    )
}

build_check_trigger() {
    make -C check-trigger
}

get_ubuntu_image() {
    # FIXME: ask ubuntu-image team to create uc20 git branch *or*
    #        switch to Maciej snap-create-image tool
    REPO="https://github.com/mvo5/ubuntu-image.git"
    BRANCH="uc20-recovery"
    
    git clone -b "$BRANCH" "$REPO"
}

get_snapd_uc20() {
    REPO="https://github.com/snapcore/snapd.git"
    BRANCH="uc20"
    
    GOPATH="$(pwd)/go"
    DST="$GOPATH/src/github.com/snapcore/snapd"
    
    # fake GOPATH
    export GOPATH
    mkdir -p "$DST"
    if [ ! -d "$DST/cmd/snap" ]; then
        git clone -b "$BRANCH" "$REPO" "$DST"
    fi
    (cd "$DST" && ./get-deps.sh)

    go build -o go/snap github.com/snapcore/snapd/cmd/snap
    go build -o go/snapd github.com/snapcore/snapd/cmd/snapd
}

get_shim_uc20() {
    sudo apt install gnu-efi

    REPO="https://github.com/cmatsuoka/shim.git"
    BRANCH="uc20"

    if [ ! -d shim ]; then
        git clone -b "$BRANCH" "$REPO"
    fi

    make -C shim \
        RELEASE=15 \
        MAKELEVEL=0 \
        EFI_PATH=/usr/lib \
        ENABLE_HTTPBOOT=true \
        ENABLE_SHIM_CERT=1 \
        ENABLE_SBSIGN=1 \
        VENDOR_CERT_FILE=../canonical-uefi-ca.der
        EFIDIR=ubuntu

    (cd shim;
    sbsign \
        --key ../sb-test-cc/TestUefiCA.key \
        --cert ../sb-test-cc/TestUefiCA.crt.pem \
        --output shimx64.efi.signed \
        shimx64.efi
    )
}

get_fde_utils() {
    REPO="https://github.com/chrisccoulson/ubuntu-core-fde-utils"
    BRANCH="master"

    GOPATH="$(pwd)/go"
    DST="$GOPATH/src/github.com/chrisccoulson/ubuntu-core-fde-utils"

    # fake GOPATH
    export GOPATH
    mkdir -p "$DST"
    if [ ! -d "$DST/unlock" ]; then
        git clone -b "$BRANCH" "$REPO" "$DST"
        (cd "$DST" && go get -v -d ./...)
    fi
    if [ -f "$DST"/vendor/vendor.json ]; then
        (cd "$DST" && govendor sync)
    fi

    go build -o go/unlock github.com/chrisccoulson/ubuntu-core-fde-utils/unlock
}

generate_keys() {
    echo "Generating keys..."

    TEMP=$(mktemp -d -t XXXXXXXXXX)

    cp /usr/share/OVMF/OVMF_VARS.fd .

    mkdir sbtestdb
    (cd sbtestdb

     openssl req -new -x509 -newkey rsa:2048 -keyout TestPK.key -out TestPK.crt \
        -outform DER -days 3650 -passout pass:1234 -subj "/CN=Test Platform Key"
     openssl req -new -x509 -newkey rsa:2048 -keyout TestKEK.key -out TestKEK.crt \
        -outform DER -days 3650 -passout pass:1234 -subj "/CN=Test Key Exchange Key"
     openssl req -new -x509 -newkey rsa:2048 -keyout TestUEFI.key -out TestUEFI.crt \
        -outform DER -days 3650 -passout pass:1234 -subj "/CN=Test UEFI Signing Key"

     # Copy Chris Coulson's UEFI test certificate
     cp ../sb-test-cc/TestUefiCA.crt .

     # Download Microsoft’s UEFI CA certificate
     wget --content-disposition https://go.microsoft.com/fwlink/p/?linkid=321194

     dd if=/dev/zero of=drive.img count=50 bs=1M

     mkfs.vfat drive.img
     sudo mount drive.img "$TEMP"
     sudo cp *.crt "$TEMP"
     sudo umount "$TEMP"

     rmdir "$TEMP"
    )
}

if ! snap list swtpm-mvo; then
    snap install --beta swtpm-mvo
fi

if [ ! -d ./ubuntu-image ]; then
    get_ubuntu_image
fi

if [ ! -d ./core-build ]; then
    REPO="https://github.com/snapcore/core-build.git"
    BRANCH="uc20"
    
    git clone -b "$BRANCH" "$REPO"
fi

# FIXME: once we put snapd in channel=20 this is no longer needed
#        we can just use the "snapd" snap from channel=20
if [ ! -x ./go/snap ]; then
    get_snapd_uc20
fi

if [ ! -f sbtestdb/drive.img ]; then
    generate_keys
fi

if [ ! -x ./shim/shimx64.efi.signed ]; then
    get_shim_uc20
fi

if [ ! -x ./go/unlock ]; then
    get_fde_utils
fi

if [ ! -e core20-mvo-amd64.model ]; then
    wget https://people.canonical.com/~mvo/tmp/core20-mvo-amd64.model
fi

# get the snaps
snap download --channel=18 pc-kernel
snap download snapd --edge
snap download core20 --edge
snap download --channel=20/edge pc

if [ ! -x chooser/chooser ]; then
    build_chooser
fi

if [ ! -x check-trigger/check-trigger ]; then
    build_check_trigger
fi

if [ ! -f no-udev.so ]; then
    build_udev_hack
fi

