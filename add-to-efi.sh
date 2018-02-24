#!/bin/sh
#
# MIT License
#
# Copyright (c) 2018 Hermann von Kleist <stertingen@yahoo.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

set -e

KPARAM="rw"
KPARAM_MIN="ro"

ID_TYPE="PARTUUID"
TIMEOUT=3
EFIBOOTMGR="efibootmgr"

##################################################
##################################################
##################################################

OUTPREFIX=" $(tput setaf 6)[EFI]$(tput sgr0) "
ERRPREFIX=" $(tput setaf 1)[EFI]$(tput sgr0) "

# Get name of OS
if [ -f /etc/os-release ]; then
    source /etc/os-release
else
    NAME=$(uname -o)
fi

# Find root file system
if [ "x$ID_TYPE" = "x" ] ; then
    ROOTFS=(`lsblk --list --output MOUNTPOINT,TYPE,NAME --noheadings --paths | grep "^/ " | sed 's/ \+/\n/g'`)
else
    ROOTFS=(`lsblk --list --output MOUNTPOINT,TYPE,NAME,$ID_TYPE --noheadings --paths | grep "^/ " | sed 's/ \+/\n/g'`)
    ROOT_ID=${ROOTFS[3]}
fi
ROOT_TYPE=${ROOTFS[1]}
ROOT_PATH=${ROOTFS[2]}
case $ROOT_TYPE in
    "part")
        if [ "x$ID_TYPE" = "x" ] ; then
            echo "$OUTPREFIX Root is on $ROOT_PATH"
            ROOTOPT="root=$ROOT_PATH"
        else
            echo "$OUTPREFIX Root is on $ID_TYPE=$ROOT_ID ($ROOT_PATH)"
            ROOTOPT="root=$ID_TYPE=$ROOT_ID"
        fi
        ;;
    "crypt")
        REAL_DEV=`cryptsetup status $ROOT_PATH | sed -n 's/^ \+device: \+\([^ ]\+\)/\1/p'`
        if [ "x$ID_TYPE" = "x" ] ; then
            echo "$OUTPREFIX Root is on $ROOT_PATH wich is encrypted on $REAL_DEV"
            ROOTOPT="root=$ROOT_PATH cryptdevice=$REAL_DEV:`basename $ROOT_PATH`"
        else
            REAL_ID=`blkid --output value --match-tag $ID_TYPE $REAL_DEV`
            echo "$OUTPREFIX Root is on $ROOT_PATH wich is encrypted on $ID_TYPE=$REAL_ID ($REAL_DEV)"
            ROOTOPT="root=$ROOT_PATH cryptdevice=$ID_TYPE=$REAL_ID:`basename $ROOT_PATH`"
        fi
        ;;
    *)
        echo "$ERRPREFIX Root partition has unknown type $ROOT_TYPE!"
        exit 1
        ;;
esac

# Find ESP
for DEV in `find /dev -name 'sd[a-z][0-9]'` ; do
    if udevadm info --query=property $DEV | grep -q 'ID_PART_ENTRY_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b' ; then
        ESP=$DEV
        break
    fi
done

if [ "x$ESP" = "x" ] ; then
    echo "$ERRPREFIX EFI System Partition not found!"
    exit 1
fi

ESP_DISK=`echo $ESP | sed 's/[0-9]\+$//g'`
ESP_PART=`echo $ESP | grep -o '[0-9]\+$'`

# Find out where ESP is mounted
EFIROOT=`findmnt --source $ESP --noheadings --output TARGET,SOURCE | sed -n "s| \+$ESP$||p"`
if [ "x$EFIROOT" = "x" ] ; then
    echo "$ERRPREFIX EFI System Partition not (properly) mounted!"
    exit 1
fi
echo "$OUTPREFIX ESP found on $ESP (mounted on $EFIROOT)."

# Macro for creating boot entries
entry() {
    _NAME=$1
    _KERNEL=$2
    shift; shift;
    _OPTIONS=$*
    echo "$OUTPREFIX Adding entry..."
    echo "  :::   Name   : $_NAME"
    echo "  :::   Kernel : $_KERNEL"
    echo "  :::   Options: $_OPTIONS"
    echo "$_OPTIONS" | iconv -f ascii -t ucs2 | $EFIBOOTMGR --quiet --create --disk $ESP_DISK --part $ESP_PART --loader "$_KERNEL" --label "$_NAME" --append-binary-args -
}

# Remove all boot entries starting with our name
echo "$OUTPREFIX Removing old boot entries..."
$EFIBOOTMGR | grep "$NAME" | sed 's/^Boot\([0-9A-F]*\).*/\1/g' | xargs -n 1 -I{} $EFIBOOTMGR --quiet --bootnum {} --delete-bootnum

# Look for kernels on ESP
KERNELS=`find $EFIROOT -name "vmlinu[xz]-*"`
for KERNEL in $KERNELS ; do
    
    # Lookup path for initrds
    KROOT=`dirname $KERNEL`
    
    # initrd name depends on kernel name
    KNAME=`basename $KERNEL | sed 's/vmlinu[xz]-//g'`

    # Add to entry name later
    KVER=`file -b $KERNEL | sed 's/.*version \([^ ]*\).*/\1/g'`
    
    # Kernel path seen by EFI
    EKERNEL=`echo $KERNEL | sed "s|^$EFIROOT||g"`

    # ROOT for initrd files
    EROOT=`echo $KROOT | sed "s|^$EFIROOT||g"`

    # Add Intel ucode
    if [ -f $KROOT/intel-ucode.img ] ; then
        UCODE="initrd=$EROOT/intel-ucode.img "
    fi

    # Add entries for fallback initramfs
    if [ -f $KROOT/initramfs-$KNAME-fallback.img ] ; then
        
        INITRD="initrd=$EROOT/initramfs-$KNAME-fallback.img"

        # Add entry for minimal options, if set
        if [ "x$KPARAM_MIN" != "x" ] ; then
            entry "$NAME with Kernel $KVER (minimal options)" "$EKERNEL" "$ROOTOPT $INITRD $KPARAM_MIN"
        fi
        entry "$NAME with Kernel $KVER (fallback initrd)" "$EKERNEL" "$ROOTOPT $UCODE$INITRD $KPARAM"
    fi

    # Add normal entry for kernel
    if [ -f $KROOT/initramfs-$KNAME.img ] ; then
        
        INITRD="initrd=$EROOT/initramfs-$KNAME.img"
        entry "$NAME with Kernel $KVER" "$EKERNEL" "$ROOTOPT $UCODE$INITRD $KPARAM"
    fi
done

# Set timeout
echo "$OUTPREFIX Set timeout to $TIMEOUT seconds..."
$EFIBOOTMGR --quiet --timeout $TIMEOUT
