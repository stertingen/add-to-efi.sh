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

OUTPREFIX=" $(tput setaf 6)[EFI]$(tput sgr0) "
WRNPREFIX=" $(tput setaf 3)[EFI]$(tput sgr0) "
ERRPREFIX=" $(tput setaf 1)[EFI]$(tput sgr0) "

# Default options
TIMEOUT=3
DRY_RUN='1'
VERBOSE='0'

# Option parsing
while getopts "r:e:p:t:n:k:m:dvh" opt; do
    case $opt in
        r)
            if [ -b $OPTARG ] ; then
                ROOTDEV=$OPTARG
            else
                echo $ERRPREFIX Invalid root partition: $OPTARG
                exit 1
            fi
            ;;
        e)
            if [ -b $OPTARG ] ; then
                ESP=$OPTARG
            else
                echo $ERRPREFIX Invalid EFI partition: $OPTARG
                exit 1
            fi
            ;;
        p)
            if (echo "UUID PARTUUID LABEL PARTLABEL" | grep -wq "$OPTARG") ; then
                ID_TYPE=$OPTARG
            else
                echo $ERRPREFIX Unknown ID type: $OPTARG
                exit 1
            fi
            ;;
        t)
            if (echo $OPTARG | grep -q "[0-9]\+") ; then
                TIMEOUT=$OPTARG
            else
                echo $ERRPREFIX Invalid timeout: $OPTARG
                exit 1
            fi
            ;;
        n) NAME=$OPTARG ;;
        k) KPARAM=$OPTARG ;;
        m) KPARAM_MIN=$OPTARG ;;
        d) DRY_RUN='1' ;;
        v) VERBOSE='1' ;;
        h|\?)
            echo "Usage: $0 [-r <partition>] [-e <partition>] [-p (UUID|PARTUUID|LABEL|PARTLABEL)] [-t <timeout>] [-k <kernel-param>] [-m <kernel-param>] [-d] [-h]"
            echo "-r <partition>     Set root partition."
            echo "-e <partition>     Set ESP partition."
            echo "-p <identifier>    Set identifier type, e.g. PARTUUID. Defaults to device name if unset."
            echo "-t <timeout>       Set timeout. May be useless on some systems."
            echo "-n <name>          Set OS name."
            echo "-k <kernel-param>  Set additional kernel parameters."
            echo "-m <kernel-param>  Set additional kernel parameters for minimal boot options."
            echo "-d                 Dry run."
            echo "-v                 Verbose output."
            echo "-h                 Display help."
            exit 0
            ;;
    esac
done

if [ "$DRY_RUN" = "1" ] ; then
    VERBOSE="1"
fi

# Get name of OS, if unset
if [ "x$NAME" = "x" ] ; then
    if [ -f /etc/os-release ]; then
        source /etc/os-release
    else
        NAME=$(uname -o)
    fi
fi

# Find root file system
if [ "x$ROOTDEV" = "x" ] ; then
    if [ "x$ID_TYPE" = "x" ] ; then
        ROOTFS=(`lsblk --list --output MOUNTPOINT,TYPE,NAME --noheadings --paths | grep "^/ " | sed 's/ \+/\n/g'`)
    else
        ROOTFS=(`lsblk --list --output MOUNTPOINT,TYPE,NAME,$ID_TYPE --noheadings --paths | grep "^/ " | sed 's/ \+/\n/g'`)
        ROOT_ID=${ROOTFS[3]}
    fi
    ROOT_TYPE=${ROOTFS[1]}
    ROOT_PATH=${ROOTFS[2]}
else
    if [ "x$ID_TYPE" = "x" ] ; then
        ROOTFS=(`lsblk --list --output TYPE,NAME --noheadings --paths $ROOTDEV | head -q -n 1 | sed 's/ \+/\n/g'`)
    else
        ROOTFS=(`lsblk --list --output TYPE,NAME,$ID_TYPE --noheadings --paths $ROOTDEV | head -q -n 1 | sed 's/ \+/\n/g'`)
        ROOT_ID=${ROOTFS[2]}
    fi
    ROOT_TYPE=${ROOTFS[0]}
    ROOT_PATH=${ROOTFS[1]}
fi

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
        REAL_DEV=`cryptsetup status $ROOT_PATH 2>/dev/null | sed -n 's/^ \+device: \+\([^ ]\+\)/\1/p'`
        if [ "x$REAL_DEV" = "x" ] ; then
            echo $ERRPREFIX Error while fetching crypt data for $ROOT_PATH. Try using sudo!
            exit 1
        fi
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
if [ "x$ESP" = "x" ] ; then
    for DEV in `find /dev -name 'sd[a-z][0-9]'` ; do
        if (udevadm info --query=property $DEV | grep -q 'ID_PART_ENTRY_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b') ; then
            ESP=$DEV
            break
        fi
    done

    if [ "x$ESP" = "x" ] ; then
        echo "$ERRPREFIX EFI System Partition not found!"
        exit 1
    fi
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
    echo "  :::     Name   : $_NAME"
    echo "  :::     Kernel : $_KERNEL"
    echo "  :::     Options: $_OPTIONS"
    if [ "$DRY_RUN" = "0" ] ; then
        echo "$_OPTIONS" | iconv -f ascii -t ucs2 | efibootmgr --quiet --create --disk $ESP_DISK --part $ESP_PART --loader "$_KERNEL" --label "$_NAME" --append-binary-args -
    fi
}

# Remove all boot entries starting with our name
echo "$OUTPREFIX Removing old boot entries..."
if [ "$DRY_RUN" = "0" ] ; then
    efibootmgr | grep "$NAME" | sed 's/^Boot\([0-9A-F]*\).*/\1/g' | xargs -n 1 -I{} efibootmgr --quiet --bootnum {} --delete-bootnum
fi

# Look for kernels on ESP
KERNELS=`find $EFIROOT -name "vmlinu[xz]-*" | sort -r`
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
if [ "$DRY_RUN" = "0" ] ; then
    efibootmgr --quiet --timeout $TIMEOUT
fi
