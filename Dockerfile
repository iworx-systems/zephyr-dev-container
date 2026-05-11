#Zephyr development environment

FROM debian:12.11-slim AS base

# APT packages to install while building this image and remove when done building.
ARG DOCKER_IMAGE_BUILD_PACKAGES="python3-dev python3-pip wget curl"

# Using working branch
ARG ZEPHYR_VERSION=development

# Python version to build from source
ARG PYTHON_VERSION=3.12.8

# Zephyr SDK
ARG ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk
ARG TOOLCHAIN=arm-zephyr-eabi
ARG TEST_TOOLCHAIN=x86_64-zephyr-elf

FROM base AS docker-image-build-packages

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  ${DOCKER_IMAGE_BUILD_PACKAGES}

FROM docker-image-build-packages AS python-install

ARG PYTHON_VERSION

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
    build-essential zlib1g-dev libncurses-dev libgdbm-dev libnss3-dev \
    libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev \
    liblzma-dev \
  && wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz \
  && tar -xf Python-${PYTHON_VERSION}.tgz \
  && cd Python-${PYTHON_VERSION} \
  && ./configure --prefix=/usr/local \
  && make -j$(nproc) \
  && make install \
  && cd .. \
  && rm -rf Python-${PYTHON_VERSION} Python-${PYTHON_VERSION}.tgz

FROM python-install AS utilities

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
  && pip3 install --upgrade pip \
  && python3 -m pip config set global.break-system-packages true \
  && pip3 install clang-format \
  && pip3 install pre-commit \
  && pip3 install west \
  && pip3 install \
  -r https://raw.githubusercontent.com/iworx-systems/zephyr/${ZEPHYR_VERSION}/scripts/requirements.txt \
  && pip3 install cmake \
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
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  protobuf-compiler \
  python3-protobuf \
  device-tree-compiler \
  ninja-build \
  xz-utils \
  && export zephyr_sdk_version="$(curl https://raw.githubusercontent.com/iworx-systems/zephyr/${ZEPHYR_VERSION}/SDK_VERSION)" \
  && export sdk_file_name="zephyr-sdk-${zephyr_sdk_version}_linux-$(uname -m)_minimal.tar.xz" \
  && wget -q "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${zephyr_sdk_version}/${sdk_file_name}" \
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
  xz-utils file make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1 \
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

FROM codechecker AS nodejs
# I need to install node for the dts-linter used in Zephyr's compliance checks

ARG NODE_MAJOR=22

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends ca-certificates gnupg \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
  && apt-get -y update \
  && apt-get -y install --no-install-recommends nodejs \
  && mkdir -p /tmp/zephyr-ci \
  && curl -fsSL -o /tmp/zephyr-ci/package.json https://raw.githubusercontent.com/iworx-systems/zephyr/${ZEPHYR_VERSION}/scripts/ci/package.json \
  && curl -fsSL -o /tmp/zephyr-ci/package-lock.json https://raw.githubusercontent.com/iworx-systems/zephyr/${ZEPHYR_VERSION}/scripts/ci/package-lock.json \
  && npm --prefix /tmp/zephyr-ci ci \
  && rm -rf /tmp/zephyr-ci \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM nodejs AS doc

WORKDIR /opt

RUN \
  apt-get -y update \
  && apt-get -y install \
  default-jre \
  graphviz \
  && mkdir plantuml

COPY plantuml-1.2026.3beta7.jar plantuml/plantuml.jar

FROM doc AS iworx_zephyr_apps_runtime

RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends \
  dfu-util \
  uhubctl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM iworx_zephyr_apps_runtime AS cleanup-docker-image-build-tools

RUN \
  apt-get remove -y --purge \
  ${DOCKER_IMAGE_BUILD_PACKAGES} \
  && apt-get clean \
  && pip3 install pyusb \
  && pip3 install libusb1 \
  && pip3 install libusb-package \
  && pip3 install pyocd[pack] \
  && pip3 install cmsis-pack-manager \
  && rm -rf /var/lib/apt/lists/*

FROM cleanup-docker-image-build-tools AS claude

RUN npm install -g @anthropic-ai/claude-code

FROM claude AS startup

WORKDIR /root
