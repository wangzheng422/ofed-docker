#!/bin/bash -x
MOFED=/run/mellanox/drivers
NVIDIA=/run/nvidia/drivers
KERNEL_VERSION=$(uname -r)

function set_driver_readiness() {
    touch /.driver-ready
}

function unset_driver_readiness() {
    rm -f /.driver-ready
}

function exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "ERROR: command execution failed: $1"
        exit 1
    fi
}

# has_files_matching() $1: dir path, $2: grep pattern
function has_files_matching() {
    local DIR_PATH=$1
    local PATTERN=$2
    ls $DIR_PATH 2> /dev/null | grep -E "${PATTERN}" > /dev/null
    return $?
}

function install_prereq_runtime() {
    # echo "Checking for entitlement"
    # ls -l /etc/pki/entitlement-host
    # echo "Enabling RHOCP and EUS RPM repos..."
    # dnf config-manager --set-enabled rhocp-4.6-for-rhel-8-x86_64-rpms || true
    # dnf config-manager --set-enabled rhel-8-for-x86_64-baseos-eus-rpms  || true
    # Install linux headers
    echo "Installing kernel packages & dependencies"
    # TODO: Use os-release to set releasever
    # dnf -y --releasever=8.2 install kernel-core-${KERNEL_VERSION} kernel-headers-${KERNEL_VERSION} kernel-devel-${KERNEL_VERSION} binutils-devel elfutils-libelf-devel gcc make
    yum -y install kernel-bek-core-${KERNEL_VERSION} kernel-bek-headers-${KERNEL_VERSION} kernel-bek-devel-${KERNEL_VERSION} binutils-devel elfutils-libelf-devel gcc make
    return $?
}

function inject_mofed_driver() {
    echo "Trying to find OFED drivers"
    if [[ -e ${MOFED}/usr/src/ofa_kernel ]]; then
        ln -sf ${MOFED}/usr/src/ofa_kernel /usr/src/ofa_kernel
    else
        echo "ERROR: Mellanox NIC driver sources not found."
        return 1
    fi

    has_files_matching ${MOFED}/usr/lib/modules/${KERNEL_VERSION}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox mlx5
    if  [[ $? -eq 0 ]]; then
	mkdir -p /usr/lib/modules/${KERNEL_VERSION}/extra/mlnx-ofa_kernel/drivers/net/ethernet/
        ln -sf  ${MOFED}/usr/lib/modules/${KERNEL_VERSION}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox/ /usr/lib/modules/${KERNEL_VERSION}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox
    else
        echo "ERROR: Failed to locate Mellanox NIC drivers in mount: ${MOFED}"
        return 1
    fi
}

function inject_nvidia_driver() {
    # NVIDIA driver may be installed either with/out dkms which affects the module location
    # always inject the modules under dkms as thats where nv_peer_mem is looking for the modules
    # alternative is to modify nv_peer_mem/create_nv_symvers.sh to support both locations
    echo "Trying to find GPU drivers"
    has_files_matching ${NVIDIA}/usr/src/ nvidia-*
    if  [[ $? -eq 0 ]]; then
        ln -sf ${NVIDIA}/usr/src/nvidia-* /usr/src/.
    else
        echo "ERROR: Nvidia GPU driver sources not found."
        return 1
    fi

    has_files_matching ${NVIDIA}/lib/modules/${KERNEL_VERSION}/kernel/drivers/video/ nvidia
    if [[ $? -eq 0 ]]; then
        # Driver installed as non-dkms kernel module
        ln -sf ${NVIDIA}/lib/modules/${KERNEL_VERSION}/kernel/drivers/video/nvidia* /lib/modules/${KERNEL_VERSION}/kernel/drivers/video/
    else
        echo "ERROR: Failed to locate Nvidia GPU drivers in mount: ${NVIDIA}"
        return 1
    fi
}

function prepare_build_env() {
    ls -al /
    # Patch filesystem with components from both Mellanox and Nvidia Drivers
    touch /lib/modules/${KERNEL_VERSION}/modules.order && \
    touch /lib/modules/${KERNEL_VERSION}/modules.builtin && \
    mkdir -p /etc/infiniband && \
    cp /root/nv_peer_memory/nv_peer_mem.conf /etc/infiniband/ && \
    inject_mofed_driver && \
    inject_nvidia_driver
    return $?
}

function build_modules() {
    # Build NV PEER MEMORY module
    cd /root/nv_peer_memory && \
    sed -i 's/updates\/dkms/kernel\/drivers\/video/g' create_nv.symvers.sh  && \
    ./build_module.sh && \
    rpmbuild --rebuild /tmp/nvidia_peer_memory-* && \
    rpm  -ivh /root/rpmbuild/RPMS/x86_64/nvidia_peer_memory-*.rpm && \
    ./nv_peer_mem restart && \
    ./nv_peer_mem status
    return $?
}

function handle_signal() {
    echo 'Stopping nv_peer_memory driver'
    unset_driver_readiness
    /root/nv_peer_memory/nv_peer_mem stop
}

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
exit_on_error install_prereq_runtime
exit_on_error prepare_build_env
exit_on_error build_modules
set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity & wait
