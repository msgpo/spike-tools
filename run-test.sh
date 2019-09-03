#!/bin/sh

TPM="/var/snap/swtpm-mvo/current/"

usage() {
    echo "Usage: $0 [-c]"
    exit
}

while getopts "hc" opt; do
    case "${opt}" in
        c)
            sudo rm -f "$TPM"/tpm2-00.permall
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


sudo kvm \
  -smp 2 -m 512 -netdev user,id=mynet0,hostfwd=tcp::8022-:22,hostfwd=tcp::8090-:80 \
  -object rng-random,filename=/dev/hwrng,id=rng0 -device virtio-rng-pci,rng=rng0 \
  -device virtio-net-pci,netdev=mynet0 \
  -pflash /usr/share/OVMF/OVMF_CODE.fd \
  -drive file=OVMF_VARS.fd,if=pflash,format=raw \
  -chardev socket,id=chrtpm,path="$TPM"/swtpm-sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
  -drive file=pc.img,format=raw \
  -drive file=sbtestdb/drive.img
