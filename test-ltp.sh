#!/bin/bash

# build the kernel and copy to temporary location
build_kernel() {
  cd $KERNEL_TREE

  if [[ "$KERNEL_VERSION" != "" ]]; then
    git checkout $KERNEL_VERSION
  fi

  if [ -f .config ]; then
    cp .config config.ltp_test.bak
  fi

  make defconfig
  make silentoldconfig

  make -j $(getconf _NPROCESSORS_ONLN) CC=gcc-7
  make INSTALL_MOD_PATH=${MODS_DIR} modules_install CC=gcc-7
  cp $KERNEL_TREE/arch/x86/boot/bzImage $KERNEL_IMAGE
  KVER=$(make kernelrelease)
}

# build LTP and install to temporary location
build_ltp() {
  cd ${LTP_TREE}
  ./configure --prefix=${LTP_DIR}
  make -j $(getconf _NPROCESSORS_ONLN)
  make install
}

build_ramdisk() {
# these binaries are going to be installed
  local INSTALL="lsblk find sort parted getopt tput column date dirname   \
	        mktemp ps diff awk timeout time losetup truncate wc grep \
	        stat basename cut sg_inq realpath findmnt vi dd \
	        sed rm rmdir lspci"

 dracut --no-compress --kver $KVER --kmoddir $MODS_DIR --no-hostonly --no-hostonly-cmdline \
	--modules "bash base systemd systemd-initrd dracut-systemd" --tmpdir $INITRD_DIR \
	--force $INITRD_IMAGE --install "$INSTALL" \
	--include "$LTP_DIR" "/opt/ltp"

}

setup_workarea() {
  TMPDIR=$(mktemp -d)
  echo $TMPDIR
  # make sure the temporary directory is created
  if [[ $? != 0 ]]; then
	  echo "Unable to create temporary directory!"
	  echo "Exiting."
	  exit -1
  fi
  INITRD_DIR=${TMPDIR}/initrd
  INITRD_IMAGE=${INITRD_DIR}/initrd

  KERNEL_IMAGE=${TMPDIR}/bzImage
  MODS_DIR=${TMPDIR}/modules

  LTP_DIR=${TMPDIR}/ltp

  mkdir -p $INITRD_DIR
  mkdir -p $MODS_DIR
  mkdir -p $LTP_DIR

  trap "rm -rf $TMPDIR" EXIT
}

run_qemu() {
  qemu-system-x86_64 -m 512M -smp 2 -nographic \
     -serial mon:stdio -enable-kvm \
     -kernel $KERNEL_IMAGE \
     -append console=ttyS0 -initrd $INITRD_IMAGE
}

check_requirements() {
  if [[ "$KERNEL_TREE" == "" ]]; then
	  echo "You must specify your kernel tree!"
	  usage
  fi
  if [[ "$LTP_TREE" == "" ]]; then
	  echo "You must specify your ltp tree!"
	  usage
  fi
  # dont run this as root
  if [[ "$EUID" == "0" ]]
    then echo "Please do not run as root"
    exit -1
  fi

  for cmd in dracut git make qemu-system-x86_64; do
    if ! command -v $cmd 2>&1>/dev/null; then
      echo "please install $cmd"
      exit -1
    fi
  done
}

usage() {
  echo "Usage: $(basename $0) -k /path/to/kernel -l /path/to/ltp [-v kernel version] [-h] [-t] [-c compiler] "
  echo "   -k :	path to your kernel tree"
  echo "   -l : path to your ltp tree"
  echo "   -v : git tag or hash for linux kernel"
  echo "   -t : testcase to run in QEMU. Not yet implemented"
  echo "   -h : show this help and exit"
  echo "   -c : what compiler to pass to makefiles (e.g. gcc-7)"
  exit
}

CC=""
while getopts ":l:k:t:v:h" opt; do
  case $opt in
    k)
	echo "using kernel at: $OPTARG" >&2
	KERNEL_TREE="$OPTARG"
	;;
    l)
	echo "using ltp tree at: $OPTARG" >&2
	LTP_TREE="$OPTARG"
	;;
    h)
	usage
	;;
    t)
	echo "using testcase: $OPTARG" >&2
	TESTCASE="$OPTARG"
	;;
    v)
	echo "using kernel version: $OPTARG" >&2
	KERNEL_VERSION="$OPTARG"
	;;
    :)
	echo "Option -$OPTARG requires an Argument." >&2
	;;
  esac
done


check_requirements
setup_workarea
build_kernel
build_ltp
build_ramdisk

run_qemu
