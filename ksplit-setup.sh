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

# Install llvm-10 from apt.llvm.org
install_llvm() {
  if [ $(clang --version | grep -o "version [0-9\.]\+" | awk '{print $2}') != "10.0.1" ]; then
    echo "Downloading llvm script to ${HOME}/llvm.sh" >> ${LOG_FILE}
    wget https://apt.llvm.org/llvm.sh -O ${HOME}/llvm.sh
    chmod +x ${HOME}/llvm.sh
    sudo ${HOME}/llvm.sh ${LLVM_VERSION}
    sudo ./update-alternatives-clang.sh ${LLVM_VERSION} 200
  fi
}

install_dependencies() {
  echo "Installing dependencies..." >> ${LOG_FILE}
  sudo apt update
  sudo apt install -y build-essential nasm cmake libelf-dev libncurses5-dev gawk linux-headers-$(uname -r)
  install_llvm
}

prepare_local_partition() {
  if [ x$(sudo file -sL /dev/sda4 | grep -o ext4) == x"" ]; then
    echo "Preparing local partition ..." >> ${LOG_FILE}
    sudo mkfs.ext4 -Fq /dev/sda4
    sudo mkdir ${MOUNT_DIR}
    sudo mount -t ext4 /dev/sda4 ${MOUNT_DIR}
    sudo chown -R ${USER}:${GROUP} ${MOUNT_DIR}
  else
    sudo mount -t ext4 /dev/sda4 ${MOUNT_DIR}
    sudo chown -R ${USER}:${GROUP} ${MOUNT_DIR}
  fi
}

prepare_machine() {
  install_dependencies
  prepare_local_partition
}

# Clone all repos
clone_pdg() {
  if [ ! -d ${MOUNT_DIR}/pdg ]; then
    echo "Cloning PDG" >> ${LOG_FILE}
    pushd ${MOUNT_DIR}
    git clone https://github.com/ARISTODE/program-dependence-graph.git pdg --recursive --branch dev_ksplit
    popd;
  else
    echo "PDG dir not empty! skipping..." >> ${LOG_FILE}
  fi
}

clone_bareflank() {
  if [ ! -d ${MOUNT_DIR}/bflank ]; then
    mkdir -p ${MOUNT_DIR}/bflank;
    echo "Cloning Bareflank" >> ${LOG_FILE}
    pushd ${MOUNT_DIR}/bflank
    git clone https://github.com/mars-research/lvd-bflank.git bflank --depth 100 --branch dev_ksplit
    mkdir cache build
    popd;
  else
    echo "Bareflank dir not empty! skipping..." >> ${LOG_FILE}
  fi
}

clone_linux() {
  if [ ! -d ${MOUNT_DIR}/lvd-linux ]; then
    echo "Cloning LVD linux" >> ${LOG_FILE}
    pushd ${MOUNT_DIR}
    git clone https://github.com/mars-research/lvd-linux/ --branch dev_ksplit --depth 500 --recursive
    popd;
  else
    echo "lvd-linux dir not empty! skipping..." >> ${LOG_FILE}
  fi
}

clone_bcfiles() {
  if [ ! -d ${MOUNT_DIR}/bc-files ]; then
    echo "Cloning bc-files" >> ${LOG_FILE}
    pushd ${MOUNT_DIR}
    git clone https://gitlab.flux.utah.edu/xcap/bc-files.git --depth 1
    popd;
  else
    echo "bc-files dir not empty! skipping..." >> ${LOG_FILE}
  fi
}

clone_repos() {
  clone_pdg;
  clone_bareflank;
  clone_linux;
  clone_bcfiles;
}

## Build
build_svf() {
  echo "Building PDG" >> ${LOG_FILE}
  pushd ${MOUNT_DIR}/pdg/SVF
  mkdir -p build && cd build;
  cmake .. && make -j $(nproc)
}

build_pdg() {
  echo "Building PDG" >> ${LOG_FILE}
  build_svf;
  pushd ${MOUNT_DIR}/pdg
  mkdir -p build && cd build;
  cmake .. && make -j $(nproc)
}

build_bareflank(){
  echo "Building bareflank" >> ${LOG_FILE}
  pushd ${MOUNT_DIR}/bflank/build
  mv ../bflank/config.cmake ..
  cmake ../bflank
  make -j $(nproc)
  popd;
}

build_module_init_tools(){
  if [ x$(command -v lcd-insmod) == x"" ]; then
    echo "Building module init tools" >> ${LOG_FILE}
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
  echo "Building lcd-domains" >> ${LOG_FILE}
  pushd lcd-domains;
  # do NOT use -j as it corrupts the .o files
  make
  popd;
}

build_linux() {
  echo "Building Linux" >> ${LOG_FILE}
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

build_all() {
  build_pdg;
  build_bareflank;
  build_linux;
}

prepare_machine;
clone_repos;
build_all;
