FROM quay.io/wangzheng422/qimgs:mofed-wzh-5.2-2.2.0.0-2021-03-28-1150-bclinux7.6-amd64-base

# migrate to bclinux
RUN yum -y downgrade systemd-libs libselinux openssl-libs libcom_err krb5-libs systemd krb5-libs binutils

# Install packages
RUN yum install -y autoconf git ncurses-devel openssl openssl-devel rpm-build systemd-devel

WORKDIR /root
# Clone Repo
# ARG D_NV_PEER_MEM_BRANCH=master
# RUN git clone --branch ${D_NV_PEER_MEM_BRANCH} https://github.com/Mellanox/nv_peer_memory.git && \
#     echo "ulimit -c: " && ulimit -c
COPY nv_peer_memory ./nv_peer_memory
RUN echo "ulimit -c: " && ulimit -c

RUN chmod +x /root/nv_peer_memory/build_module.sh /root/nv_peer_memory/build_release.sh /root/nv_peer_memory/create_nv.symvers.sh /root/nv_peer_memory/nv_peer_mem

ADD ./entrypoint.sh ./
RUN chmod +x /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
