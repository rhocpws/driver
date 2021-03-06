FROM registry.access.redhat.com/ubi8:latest

COPY CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo
COPY RPM-GPG-KEY-centosofficial /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
COPY nvidia-container-runtime.repo /etc/yum.repos.d/nvidia-container-runtime.repo
#RUN curl -s -L https://raw.githubusercontent.com/rhocpws/driver/master/nvidia-container-runtime.repo | \
#    tee /etc/yum.repos.d/nvidia-container-runtime.repo

RUN sed -i 's/repo_gpgcheck=1/repo_gpgcheck=0/g' /etc/yum.repos.d/nvidia-container-runtime.repo

RUN yum install nvidia-container-runtime-hook -y --downloadonly --downloaddir=/tmp
RUN rpm -ivh --nodigest --nofiledigest /tmp/*.rpm
RUN rm /tmp/*.rpm

#RUN rpm -ivh https://nvidia.github.io/libnvidia-container/centos7/x86_64/libnvidia-container1-1.0.5-1.x86_64.rpm
#RUN rpm -ivh https://nvidia.github.io/libnvidia-container/centos7/x86_64/libnvidia-container-tools-1.0.5-1.x86_64.rpm
#RUN rpm -ivh https://nvidia.github.io/nvidia-container-runtime/centos7/x86_64/nvidia-container-toolkit-1.0.5-2.x86_64.rpm

RUN sed -i 's/#root/root/g' /etc/nvidia-container-runtime/config.toml
RUN sed -i 's/#path.*/path = "\/run\/nvidia\/driver\/usr\/bin\/nvidia-container-cli"/g' /etc/nvidia-container-runtime/config.toml
RUN sed -i 's/#debug/debug/g' /etc/nvidia-container-runtime/config.toml


RUN yum install -y \
        kernel-headers-$(uname -r) \
        ca-certificates \
        curl \
        gcc \
        glibc.i686 \
        make \
        cpio \
        kmod && \
    rm -rf /var/cache/yum/*

COPY extract-vmlinux /usr/local/bin/extract-vmlinux
RUN curl -fsSL -o /usr/local/bin/donkey https://github.com/3XX0/donkey/releases/download/v1.1.0/donkey && \
    chmod +x /usr/local/bin/donkey /usr/local/bin/extract-vmlinux

#ARG BASE_URL=http://us.download.nvidia.com/XFree86/Linux-x86_64
ARG BASE_URL=https://us.download.nvidia.com/tesla
ARG DRIVER_VERSION=418.87.01
ARG SHORT_DRIVER_VERSION=418.87
ENV DRIVER_VERSION=$DRIVER_VERSION

# Install the userspace components and copy the kernel module sources.
RUN cd /tmp && \
    curl -fSsl -O $BASE_URL/$SHORT_DRIVER_VERSION/NVIDIA-Linux-x86_64-$DRIVER_VERSION.run && \
    sh NVIDIA-Linux-x86_64-$DRIVER_VERSION.run -x && \
    cd NVIDIA-Linux-x86_64-$DRIVER_VERSION && \
    ./nvidia-installer --silent \
                       --no-kernel-module \
                       --install-compat32-libs \
                       --no-nouveau-check \
                       --no-nvidia-modprobe \
                       --no-rpms \
                       --no-backup \
                       --no-check-for-alternate-installs \
                       --no-libglx-indirect \
                       --no-install-libglvnd \
                       --x-prefix=/tmp/null \
                       --x-module-path=/tmp/null \
                       --x-library-path=/tmp/null \
                       --x-sysconfig-path=/tmp/null \
                       --no-glvnd-egl-client \
                       --no-glvnd-glx-client && \
    mkdir -p /usr/src/nvidia-$DRIVER_VERSION && \
    mv LICENSE mkprecompiled kernel /usr/src/nvidia-$DRIVER_VERSION && \
    sed '9,${/^\(kernel\|LICENSE\)/!d}' .manifest > /usr/src/nvidia-$DRIVER_VERSION/.manifest && \
    rm -rf /tmp/*

COPY nvidia-driver /usr/local/bin
COPY CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo
COPY RPM-GPG-KEY-centosofficial /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

WORKDIR /usr/src/nvidia-$DRIVER_VERSION

ARG PUBLIC_KEY=empty
COPY ${PUBLIC_KEY} kernel/pubkey.x509

ARG PRIVATE_KEY
ARG KERNEL_VERSION=latest

# Compile the kernel modules and generate precompiled packages for use by the nvidia-installer.
RUN yum makecache -y && yum install -y elfutils-libelf-devel && \
    for version in $(echo $KERNEL_VERSION | tr ',' ' '); do \
        nvidia-driver update -k $version -t builtin ${PRIVATE_KEY:+"-s ${PRIVATE_KEY}"}; \
    done && \
    rm -rf /var/cache/yum/*



ENTRYPOINT ["nvidia-driver", "init"]
