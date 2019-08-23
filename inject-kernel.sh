#!/bin/bash
#
# Use this script to quickly inject a new kernel from a deb into the
# kernel snap.
#
# Example:
# $ ./inject-kernel -o kernel.snap ../kernel_214.snap linux-image.deb linux-modules.deb


source /usr/share/initramfs-tools/hook-functions

set -e

unsquash() {
    echo "Unsquashing $kernel_snap..."
    unsquashfs -d "$rootdir" "$kernel_snap"
    rm "$rootdir"/vmlinuz*
    rm "$rootdir"/initrd.img-*
}

extract() {
    echo "Extracting initramfs..."
    unmkinitramfs "$rootdir/initrd.img" "$fsdir"
}

extract_kernel() {
    echo "Extracting kernel..."
    mkdir "$tmpdir"/kernel
    local dir="$PWD"
    (cd "$tmpdir"/kernel
     ar x "$dir/$kernel_deb"
     tar xf data.tar.*
     ar x "$dir/$modules_deb"
     tar xf data.tar.*
    )
    kversion=$(basename "$tmpdir"/kernel/lib/modules/*)
    echo "Kernel version is $kversion"
    echo "Updating snap modules..."
    rm -Rf "$rootdir"/lib/modules/[0-9]*
    cp -rap "$tmpdir/kernel/lib/modules/$kversion" "$rootdir/lib/modules/"
}

add_kernel() {
    cp "$tmpdir"/kernel/boot/vmlinuz-* "$rootdir/kernel.img"
    ln -s kernel.img "$rootdir/vmlinuz"
    ln -s kernel.img "$rootdir/vmlinuz-$kversion"
    rm "$rootdir"/config-*
    cp "$tmpdir/kernel/boot/config-$kversion" "$rootdir"/
}

add_modules() {
    if [ ! -d "$tmpdir/fs/main/lib/modules/$kversion" ]; then
        mv "$tmpdir"/fs/main/lib/modules/* "$tmpdir/fs/main/lib/modules/$kversion"
    fi
    for i in $(find "$tmpdir/fs/main/lib/modules/" -name "*.ko"); do
        local m=$(echo $i | sed -e "s@$tmpdir/fs/main/lib/modules/[^/]*/@@")
        if [ -f "$tmpdir/kernel/lib/modules/$kversion/$m" ]; then
            cp "$tmpdir/kernel/lib/modules/$kversion/$m" "$i"
        fi
    done

    depmod -b "$fsdir/main" "$kversion"
    depmod -b "$rootdir" "$kversion"
}

repack() {
    echo "Repacking initramfs..."
    (cd "$fsdir/early"; find . | cpio -H newc -o) > "$rootdir/initrd.img"
    (cd "$fsdir/main"; find . | cpio -H newc -o | gzip -c) >> "$rootdir/initrd.img"
    ln -s initrd.img "$rootdir/initrd.img-$kversion"
}

resquash() {
    if [ -z "$output" ]; then
        num=1
        while [ -f "$kernel_snap.$num" ]; do
            num=$((num + 1))
        done
        output="$kernel_snap.$num"
    fi
    mksquashfs "$rootdir" "$output" -noappend -comp gzip -no-xattrs -no-fragments
    echo "Created $output"
}

usage() {
    echo "Usage: $0 [-o output] <kernel snap> <linux-image deb> <linux-modules deb>"
    exit
}


while getopts "ho:" opt; do
    case "${opt}" in
        o)
            output="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -lt 3 ]; then
    usage
fi


kernel_snap="$1"
kernel_deb="$2"
modules_deb="$3"
tmpdir=$(mktemp -d -t inject-XXXXXXXXXX)
rootdir="$tmpdir/root"
fsdir="$tmpdir/fs"


function finish {
    echo "Cleaning up"
    rm -Rf "$tmpdir"
}
trap finish EXIT

unsquash
extract
extract_kernel
add_kernel
add_modules
repack
resquash

