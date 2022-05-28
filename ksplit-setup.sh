#!/bin/bash

MOUNT_DIR=/opt/ksplit
LOG_FILE=${HOME}/ksplit-setup.log
LLVM_VERSION=10

USER=${SUDO_USER}

if [[ ${USER} == "" ]]; then
  USER=$(id -u -n)
fi

if [[ ${SUDO_GID} == "" ]]; then
  GROUP=$(id -g -n)
else
  GROUP=$(getent group  | grep ${SUDO_GID} | cut -d':' -f1)
fi

BCFILES_GIT_REPO="https://github.com/ksplit/bc-files.git"
BFLANK_GIT_REPO="https://github.com/ksplit/bflank.git"
IDLC_GIT_REPO="https://github.com/ksplit/idlc.git"
LVDKERNEL_GIT_REPO="https://github.com/ksplit/lvd-linux.git"
PDG_GIT_REPO="https://github.com/ksplit/pdg.git"

record_log() {
  echo "[$(date)] $1" >> ${LOG_FILE}
}

# Install llvm-10 from apt.llvm.org
install_llvm() {
  if [ $(clang --version | grep -o "version [0-9\.]\+" | awk '{print $2}') != "10.0.1" ]; then
    record_log "Downloading llvm script to ${HOME}/llvm.sh"
    wget https://apt.llvm.org/llvm.sh -O ${HOME}/llvm.sh
    chmod +x ${HOME}/llvm.sh
    sudo ${HOME}/llvm.sh ${LLVM_VERSION}
    sudo ./update-alternatives-clang.sh ${LLVM_VERSION} 200
  fi
}

install_dependencies() {
  record_log "Begin setup!"
  record_log "Installing dependencies..."
  sudo apt update
  sudo apt install -y build-essential nasm cmake libelf-dev libncurses5-dev gawk linux-headers-$(uname -r)
  install_llvm
}

create_extfs() {
  record_log "Creating ext4 filesystem on /dev/sda4"
  sudo mkfs.ext4 -Fq /dev/sda4
}

mountfs() {
  sudo mkdir ${MOUNT_DIR}
  sudo mount -t ext4 /dev/sda4 ${MOUNT_DIR}

  if [[ $? != 0 ]]; then
    record_log "Partition might be corrupted"
    create_extfs
    mountfs
  fi

  sudo chown -R ${USER}:${GROUP} ${MOUNT_DIR}
}

prepare_local_partition() {
  record_log "Preparing local partition ..."

  MOUNT_POINT=$(mount -v | grep "/dev/sda4" | awk '{print $3}')

  if [[ x"${MOUNT_POINT}" == x"${MOUNT_DIR}" ]];then
    record_log "/dev/sda4 is already mounted on ${MOUNT_POINT}"
    return
  fi

  if [ x$(sudo file -sL /dev/sda4 | grep -o ext4) == x"" ]; then
    create_extfs;
  fi

  mountfs
}

prepare_machine() {
  install_dependencies
  prepare_local_partition
}

# Clone all repos
clone_pdg() {
  if [ ! -d ${MOUNT_DIR}/pdg ]; then
    record_log "Cloning PDG"
    pushd ${MOUNT_DIR}
    git clone ${PDG_GIT_REPO} pdg --recursive --branch dev_ksplit
    popd;
  else
    record_log "PDG dir not empty! skipping..."
  fi
}

clone_bareflank() {
  if [ ! -d ${MOUNT_DIR}/bflank ]; then
    mkdir -p ${MOUNT_DIR}/bflank;
    record_log "Cloning Bareflank"
    pushd ${MOUNT_DIR}/bflank
    git clone ${BFLANK_GIT_REPO} bflank --depth 100 --branch dev_ksplit
    mkdir cache build
    popd;
  else
    record_log "Bareflank dir not empty! skipping..."
  fi
}

clone_linux() {  if [ ! -d ${MOUNT_DIR}/lvd-linux ]; then
    record_log "Cloning LVD linux"
    pushd ${MOUNT_DIR}
    git clone ${LVDKERNEL_GIT_REPO} --branch dev_ksplit --depth 500 --recursive
    popd;
  else
    record_log "lvd-linux dir not empty! skipping..."
  fi
}

clone_bcfiles() {
  if [ ! -d ${MOUNT_DIR}/bc-files ]; then
    record_log "Cloning bc-files"
    pushd ${MOUNT_DIR}
    git clone ${BCFILES_GIT_REPO} --depth 1
    popd;
  else
    record_log "bc-files dir not empty! skipping..."
  fi
}

clone_idlc() {
  if [ ! -d ${MOUNT_DIR}/lcds-idl ]; then
    record_log "Cloning lcds-idl"
    pushd ${MOUNT_DIR}
    git clone ${IDLC_GIT_REPO} --branch feature-locks
    popd;
  else
    record_log "lcds-idl dir not empty! skipping..."
  fi
}

clone_repos() {
  clone_pdg;
  clone_bareflank;
  clone_linux;
  clone_bcfiles;
  clone_idlc;
}

## Build
build_svf() {
  record_log "Building SVF"
  pushd ${MOUNT_DIR}/pdg/SVF
  mkdir -p build && cd build;
  cmake .. && make -j $(nproc)
}

build_pdg() {
  record_log "Building PDG"
  build_svf;
  pushd ${MOUNT_DIR}/pdg
  mkdir -p build && cd build;
  cmake .. && make -j $(nproc)
}

build_bareflank(){
  record_log "Building bareflank"
  pushd ${MOUNT_DIR}/bflank/build
  mv ../bflank/config.cmake ..
  cmake ../bflank
  make -j $(nproc)
  popd;
}

build_module_init_tools(){
  if [ x$(command -v lcd-insmod) == x"" ]; then
    record_log "Building module init tools"
    pushd lcd-domains/module-init-tools;
    aclocal -I m4 && automake --add-missing --copy && autoconf
    ./configure --prefix=/ --program-prefix=lcd-
    make
    sudo make install-exec
    popd;
  fi
}

install_linux() {
  make -j $(nproc) modules
  sudo make -j $(nproc) modules_install
  sudo make -j $(nproc) headers_install
  sudo make -j install
}

build_lcd_domains() {
  record_log "Building lcd-domains"
  pushd lcd-domains;
  # do NOT use -j as it corrupts the .o files
  make
  popd;
}

build_linux() {
  record_log "Building Linux"
  pushd ${MOUNT_DIR}/lvd-linux;
  cp config_lvd .config
  make -j $(nproc)
  if [ $(uname -r) != "4.8.4-lvd" ]; then
    install_linux;
  fi
  build_module_init_tools
  build_lcd_domains
  popd;
}

build_idlc() {
  record_log "Building idlc"
  pushd ${MOUNT_DIR}/lcds-idl;
  ./setup
  mkdir -p build && cd build
  cmake ..
  make -j $(nproc)
  ./idlc
  popd
}

build_all() {
  build_pdg;
  build_bareflank;
  build_linux;
  build_idlc;
}

prepare_machine;
clone_repos;
build_all;
record_log "Done Setting up!"
