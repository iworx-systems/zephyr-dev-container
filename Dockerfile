#Zephyr development environment

FROM debian:12.11-slim AS base

# APT packages to install while building this image and remove when done building.
ARG DOCKER_IMAGE_BUILD_PACKAGES="python3-dev python3-pip wget"

ARG ZEPHYR_VERSION=main

# Zephyr SDK
ARG ZEPHYR_SDK_VERSION=0.17.1
ARG ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk
ARG TOOLCHAIN=arm-zephyr-eabi
ARG TEST_TOOLCHAIN=x86_64-zephyr-elf

FROM base AS docker-image-build-packages

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  ${DOCKER_IMAGE_BUILD_PACKAGES}

FROM docker-image-build-packages AS utilities

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  usbutils \
  minicom \
  libusb-1.0-0-dev \
  protobuf-compiler \
  git \
  gperf

FROM utilities AS python-packages

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  && python3 -m pip config set global.break-system-packages true \
  && pip3 install pre-commit \
  && pip3 install west \
  && pip3 install \
  -r https://raw.githubusercontent.com/iworx-systems/zephyr/${ZEPHYR_VERSION}/scripts/requirements-base.txt \
  && pip3 install cmake \
  # Workaround until https://github.com/zephyrproject-rtos/zephyr/issues/56215 is fixed
  && pip3 install requests \
  && pip3 install click \
  && pip3 install cryptography \
  && pip3 install cbor2 \
  && pip3 install ply \
  && pip3 install pyserial \
  && pip3 install tabulate \
  && pip3 install protobuf grpcio-tools \
  && pip3 install -U pyocd
  # This is commented because 'update' causes the build to handup.
  # Uncomment this once this pull request has been implemented: https://github.com/pyocd/cmsis-pack-manager/pull/242
  # && pyocd pack update \
  # && pyocd pack install nrf52840 \

FROM python-packages AS sdk

ENV ZEPHYR_SDK_INSTALL_DIR=${ZEPHYR_SDK_INSTALL_DIR}
ENV TOOLCHAIN=${TOOLCHAIN}

RUN \
  export sdk_file_name="zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-$(uname -m)_minimal.tar.xz" \
  && apt-get -y update \
  && apt-get -y install --no-install-recommends \
  protobuf-compiler \
  python3-protobuf \
  device-tree-compiler \
  ninja-build \
  xz-utils \
  && wget -q "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${sdk_file_name}" \
  && mkdir -p ${ZEPHYR_SDK_INSTALL_DIR} \
  && tar -xvf ${sdk_file_name} -C ${ZEPHYR_SDK_INSTALL_DIR} --strip-components=1 \
  && ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -t ${TOOLCHAIN} -t ${TEST_TOOLCHAIN} \
  && rm ${sdk_file_name}

#SSH for git authentication
RUN apt-get -y update \
    && apt-get -yqq install ssh \
    && mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com >> ~/.ssh/known_hosts \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

FROM sdk AS nrfjprog

#Install dependencies
RUN \
  apt-get -y update \
  && wget -P /tmp \
  https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/desktop-software/nrf-command-line-tools/sw/versions-10-x-x/10-23-2/nrf-command-line-tools_10.23.2_amd64.deb \
  && apt-get -y install /tmp/nrf-command-line-tools_10.23.2_amd64.deb \
  && echo '#!/bin/bash\necho not running udevadm "$@"' > /usr/bin/udevadm && chmod +x /usr/bin/udevadm \
  && apt-get install -y /opt/nrf-command-line-tools/share/JLink_Linux_V788j_x86_64.deb --fix-broken

FROM nrfjprog AS cmock_unity_module

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  xz-utils file make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1 curl \
	ruby

FROM cmock_unity_module AS renode

ARG RENODE_VERSION=1.14.0
ARG RENODE_INSTALL_DIR=/opt/renode
ARG RENODE_ARCHIVE=renode-${RENODE_VERSION}.linux-portable.tar.gz

RUN \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
    mono-complete \
    && mkdir -p ${RENODE_INSTALL_DIR} \
    && wget https://github.com/renode/renode/releases/download/v${RENODE_VERSION}/${RENODE_ARCHIVE} \
    && tar xf ${RENODE_ARCHIVE} -C ${RENODE_INSTALL_DIR} --strip-components=1 \
    && rm ./${RENODE_ARCHIVE} \
    && chmod a-w ${RENODE_INSTALL_DIR} \
    && echo "export PATH='${PATH}':${RENODE_INSTALL_DIR}" >> /etc/bash.bashrc \
    && pip3 install git+https://github.com/antmicro/dts2repl.git \
    && pip3 install robotframework

#Installing nano for convenience
FROM renode AS nano

RUN \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

FROM nano AS qemu_x86

RUN \
  apt-get -y update \
  && apt-get -y install \
  qemu-system-x86 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM qemu_x86 AS net_tools

RUN \
  apt-get -y update \
  && apt-get -y install \
  socat \
  iproute2 \
  libpcap-dev \
  autoconf \
  libtool \
  net-tools \
  iputils-ping \
  netcat-openbsd \
  bridge-utils \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM net_tools AS codechecker

RUN \
  apt-get -y update \
  && apt-get -y install \
  clang-tools \
  cppcheck \
  clang-tidy \
  && pip3 install codechecker

# FROM codechecker AS bluez

# WORKDIR /opt
# RUN \
#   apt-get -y update \
#   && apt-get -y install \
#   libreadline-dev libelf-dev elfutils libdw-dev \
#   udev libjson-c-dev libical-dev python3-docutils \
#   && git clone git://git.kernel.org/pub/scm/bluetooth/bluez.git \
#   && git clone git://git.kernel.org/pub/scm/libs/ell/ell.git \
#   && cd bluez \
#   && ./bootstrap-configure --disable-android --disable-midi \
#   && make -j$(nproc)

FROM codechecker AS doc

WORKDIR /opt

RUN \
  apt-get -y update \
  && apt-get -y install \
  default-jre \
  graphviz \
  && mkdir plantuml \
  && cd plantuml \
  && wget -q https://github.com/plantuml/plantuml/releases/download/v1.2022.14/plantuml-1.2022.14.jar \
  && mv plantuml-1.2022.14.jar plantuml.jar

FROM doc AS cleanup-docker-image-build-tools

RUN \
  apt-get remove -y --purge \
  ${DOCKER_IMAGE_BUILD_PACKAGES} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM cleanup-docker-image-build-tools AS startup

COPY init-devcontainer.sh  /usr/bin
RUN chmod +x /usr/bin/init-devcontainer.sh

WORKDIR /root
