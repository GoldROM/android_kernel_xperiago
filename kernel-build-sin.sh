#!/bin/bash

die () {
    echo >&2 "$@"
    exit 1
}

PRODUCT_DEFCNFG=$1
FSCONFIG=$2

[ "$1" = "" ] && die "product{cdb/hayabusa/..} has to be specified as first argument"
[ "$2" = "" ] && die "fsconfig.xml has to be specified as second argument"

if [ ! -f "arch/arm/configs/${PRODUCT_DEFCNFG}" ]; then
    # instead of specifying blue_cdb_defconfig, it could be 'cdb'
    PRODUCT_DEFCNFG=riogrande_${PRODUCT_DEFCNFG}_defconfig
fi

if [ ! -f "arch/arm/configs/${PRODUCT_DEFCNFG}" ]; then
    echo "Please use any of the following products:"
    for line in $(ls arch/arm/configs/riogrande_*_defconfig);
    do
        NAME=$(basename $line)
        echo " - $NAME"
    done
    exit 1
fi

if [ ! -f "$OUT/ramdisk.img" ]; then
    echo "Missing ramdisk.img in $OUT"
    exit 1
fi

echo "Using defconfig ${PRODUCT_DEFCNFG}"

#---------------------------------------------------------------------
# Check the actual number of CPUs on the machine and adjust the number
#---------------------------------------------------------------------
CPU_COUNT=`grep "^processor" /proc/cpuinfo | wc -l`
if [ $? -eq 0 -a -n "$CPU_COUNT" ] ; then
    JOBS=`expr $CPU_COUNT + 1`
    echo Found $CPU_COUNT CPUs, building with $JOBS parallel jobs.
else
    JOBS=5
    echo Unable to determine number of CPUs, defaulting to $JOBS parallel jobs.
fi

#------------------------------------------------------------
# Need this to be able to build. Taken from kernel/Android.mk
#------------------------------------------------------------
export STERICSSON_WLAN_BUILT_IN=y

if [ "$3" == "clean" ] ; then
    echo 'Cleaning build...'
    #-------------------
    # Clean up the build
    #-------------------
    ARCH=arm CROSS_COMPILE=../prebuilt/linux-x86/toolchain/arm-eabi-4.7/bin/arm-eabi- make mrproper
fi

if [ ! -e ".config" ] ; then
    echo 'No .config file, generating...'
    #---------------------------
    # kernel configuration setup
    #---------------------------
    ARCH=arm CROSS_COMPILE=../prebuilt/linux-x86/toolchain/arm-eabi-4.7/bin/arm-eabi- make $PRODUCT_DEFCNFG
fi

#------
# Build
#------
ARCH=arm CROSS_COMPILE=../prebuilt/linux-x86/toolchain/arm-eabi-4.7/bin/arm-eabi- make -j$JOBS

if [ $? -ne 0 ] ; then
    echo "Build error - skip signing"
    exit 1
fi

#------
# Sign
#------

SIN_PATH=../vendor/semc/build/sin

MKELFPY=$SIN_PATH/mkelf.py
SEMCSC=$SIN_PATH/semcsc.py
CSH=$SIN_PATH/create_sin_header

# kernel.elf
$MKELFPY -o kernel-unsigned.elf arch/arm/boot/zImage@0x00008000 \
    $OUT/ramdisk.img@0x1000000,ramdisk $OUT/cmdline.txt@cmdline

$SEMCSC -c $FSCONFIG -p Kernel -t internal -i kernel-unsigned.elf -o kernel.elf

# kernel.si_
$CSH Kernel $FSCONFIG kernel.si_
cat kernel.elf >> kernel.si_

# kernel.sin
$SEMCSC -c $FSCONFIG -p Kernel -t external -i kernel.si_ -o kernel.sin

echo "All done."
