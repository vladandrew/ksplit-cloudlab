#!/bin/bash

MOUNT_DIR=/opt/ksplit

USER=${SUDO_USER}

if [[ ${USER} == "" ]]; then
  USER=$(id -u -n)
fi

if [[ ${SUDO_GID} == "" ]]; then
  GROUP=$(id -g -n)
else
  GROUP=$(getent group  | grep ${SUDO_GID} | cut -d':' -f1)
fi

# Install llvm-10 from apt.llvm.org
install_llvm() {
  wget https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 10
  # TODO: Setup update-alternatives for clang
}

install_dependencies() {
  sudo apt update
  sudo apt install -y build-essential cmake
  install_llvm
}

prepare_local_partition() {
  GROUP=$(getent group  | grep ${SUDO_GID} | cut -d':' -f1)
  sudo mkfs.ext4 /dev/sda4
  sudo mkdir ${MOUNT_DIR}
  sudo mount -t ext4 /dev/sda4 ${MOUNT_DIR}
  sudo chown -R ${USER}:${GROUP} ${MOUNT_DIR}
}

prepare_machine() {
  install_dependencies
  prepare_local_partition
}


# Clone all repos
clone_pdg() {
  pushd ${MOUNT_DIR}
  git clone https://github.com/ARISTODE/program-dependence-graph.git pdg --recursive
  popd;
}

clone_linux() {
  pushd ${MOUNT_DIR}
  git clone https://github.com/mars-research/lvd-linux/ --branch dev_vmfunc --depth 500 --recursive
  popd;
}

clone_repos() {
  clone_pdg;
  clone_linux;
}

## Build
build_pdg() {
  pushd ${MOUNT_DIR}/pdg
  mkdir build && cd build;
  cmake .. && make -j $(nproc)
}

build_linux() {
  pushd ${MOUNT_DIR}/lvd-linux;
  cp config_lvd .config
  make -j $(nproc)
}

build_all() {
  build_pdg;
  build_linux;
}

prepare_machine;
clone_repos;
build_all;
