FROM registry.access.redhat.com/ubi8:latest

# Install packages
RUN dnf install -y autoconf git ncurses-devel openssl openssl-devel rpm-build systemd-devel

WORKDIR /root
# Clone Repo
ARG D_NV_PEER_MEM_BRANCH=master
RUN git clone --branch ${D_NV_PEER_MEM_BRANCH} https://github.com/Mellanox/nv_peer_memory.git && \
    echo "ulimit -c: " && ulimit -c

ADD ./entrypoint.sh ./

ENTRYPOINT ["/root/entrypoint.sh"]
