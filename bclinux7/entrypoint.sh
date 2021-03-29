#!/bin/bash -x

function set_driver_readiness() {
    touch /.driver-ready
}

function unset_driver_readiness() {
    rm -f /.driver-ready
}

function exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "Error occured while executing: $1"
        exit 1
    fi
}

function mount_rootfs() {
    echo "Mounting Mellanox OFED driver container rootfs..."
    mount --make-runbindable /sys
    mount --make-private /sys
    mkdir -p /run/mellanox/drivers
    mount --rbind / /run/mellanox/drivers
}

function unmount_rootfs() {
    echo "Unmounting Mellanox OFED driver rootfs..."
    if findmnt -r -o TARGET | grep "/run/mellanox/drivers" > /dev/null; then
      umount -l -R /run/mellanox/drivers
    fi
}

function handle_signal() {
    unset_driver_readiness
    unmount_rootfs
    echo "Stopping Mellanox OFED Driver..."
    /etc/init.d/openibd force-stop
    exit 0
}

function ofed_exist_for_kernel() {
    # check if mlx5_core exists in dkms under running kernel, this should be sufficient to hint us if
    # OFED drivers are installed for the running kernel
    local KVER=$(uname -r)
    if [[ -e /usr/lib/modules/${KVER}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko ]]; then
        echo "OFED driver found for kernel"
        return 0
    fi
    echo "No OFED driver found for kernel ${KVER}"
    return 1

}

function rebuild_driver() {
    # Rebuild driver in case installed driver kernel version differs from running kernel
    echo "Rebuilding driver"
    # dnf -y clean expire-cache
    # dnf -y --enablerepo=rhocp-4.6-for-rhel-8-x86_64-rpms --enablerepo=rhel-8-for-x86_64-baseos-eus-rpms --releasever=8.2 install kernel-core-$(uname -r) kernel-devel-$(uname -r) 
    yum -y install kernel-core-$(uname -r) kernel-devel-$(uname -r) 
    dkms autoinstall
}

function start_driver() {
    modprobe -r rpcrdma ib_srpt ib_isert rdma_cm
    modprobe -r i40iw ib_core
    /etc/init.d/openibd restart
    if [[ $? -ne 0 ]]; then
        echo "Error occured while restarting driver"
        return 1
    fi
    ofed_info -s
}

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
ofed_exist_for_kernel
if [[ $? -ne 0 ]]; then
    rebuild_driver
fi

exit_on_error start_driver
mount_rootfs
set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity & wait
