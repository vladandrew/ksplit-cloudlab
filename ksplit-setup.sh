#!/bin/bash

MOUNT_DIR=/opt/ksplit
LOG_FILE=${HOME}/ksplit-setup.log

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
  echo "Downloading llvm script to ${HOME}/llvm.sh" >> ${LOG_FILE}
  wget https://apt.llvm.org/llvm.sh -O ${HOME}/llvm.sh
  chmod +x ${HOME}/llvm.sh
  sudo ${HOME}/llvm.sh 10
  # TODO: Setup update-alternatives for clang
}

install_dependencies() {
  echo "Installing dependencies..." >> ${LOG_FILE}
  sudo apt update
  sudo apt install -y build-essential cmake gawk
  install_llvm
}

prepare_local_partition() {
  echo "Preparing local partition ..." >> ${LOG_FILE}
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
  echo "Cloning PDG" >> ${LOG_FILE}
  pushd ${MOUNT_DIR}
  git clone https://github.com/ARISTODE/program-dependence-graph.git pdg --recursive --branch partial_kernel
  popd;
}

clone_linux() {
  echo "Cloning LVD linux" >> ${LOG_FILE}
  pushd ${MOUNT_DIR}
  git clone https://github.com/mars-research/lvd-linux/ --branch dev_ksplit --depth 500 --recursive
  popd;
}

clone_repos() {
  clone_pdg;
  clone_linux;
}

## Build
build_pdg() {
  echo "Building PDG" >> ${LOG_FILE}
  pushd ${MOUNT_DIR}/pdg
  mkdir build && cd build;
  cmake .. && make -j $(nproc)
}

build_linux() {
  echo "Building Linux" >> ${LOG_FILE}
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
