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

if (which tput >/dev/null 2>&1) ; then
    TPUT="tput"
else
    TPUT="true"
fi

ate_print() {
    echo " $($TPUT setaf 2)[EFI]$($TPUT sgr0) $*"
}

ate_error() {
    echo " $($TPUT setaf 1)[EFI]$($TPUT sgr0) $*"
    exit 1
}

ate_debug() {
    if [ "$VERBOSE" -gt "0" ] ; then
        echo " $($TPUT setaf 3)[EFI]$($TPUT sgr0) $*"
    fi
}

ate_exec() {
    if [ "$VERBOSE" -gt "0" ] || [ "$DRY_RUN" -gt "0" ] ; then
        echo " $($TPUT setaf 5)[EFI]$($TPUT sgr0) $*"
    fi
    if [ "$DRY_RUN" = "0" ] && [ "x$DUMPTOFILE" = "x" ] ; then
        eval "$*"
    fi
    if [ "x$DUMPTOFILE" != "x" ] && [ -w $DUMPTOFILE ] ; then
        echo "$*" >> $DUMPTOFILE
    fi
}

print_help() {
    echo "Usage: $0 [-r <partition>] [-e <partition>] [-p (UUID|PARTUUID|LABEL|PARTLABEL)] [-t <timeout>] [-k <kernel-param>] [-m <kernel-param>] [-d] [-v] [-h]"
    echo "-r <partition>     Set root partition."
    echo "-e <partition>     Set ESP partition."
    echo "-p <identifier>    Set identifier type, e.g. PARTUUID. Defaults to device name if unset."
    echo "-t <timeout>       Set timeout. May be useless on some systems."
    echo "-n <name>          Set OS name."
    echo "-k <kernel-param>  Set additional kernel parameters."
    echo "-m <kernel-param>  Set additional kernel parameters for minimal boot options."
    echo "-f <file-name>     Dump commands into executable file."
    echo "-d                 Dry run."
    echo "-v                 Verbose output."
    echo "-h                 Display help."
}

# Default options
TIMEOUT=3
DRY_RUN='0'
VERBOSE='0'
DUMPTOFILE=''

# Option parsing
while getopts "r:e:p:t:n:k:m:f:dvh" opt; do
    case $opt in
        r)
            if [ -b $OPTARG ] ; then
                ROOT_DEV=$OPTARG
                ate_debug "Set root partition to $ROOT_DEV"
            else
                ate_error "Invalid root partition: $OPTARG"
            fi
            ;;
        e)
            if [ -b $OPTARG ] ; then
                ESP=$OPTARG
                ate_debug "Set EFI partition to $ESP"
            else
                ate_error "Invalid EFI partition: $OPTARG"
            fi
            ;;
        p)
            if (echo "UUID PARTUUID LABEL PARTLABEL" | grep -wq "$OPTARG") ; then
                ID_TYPE=$OPTARG
                ate_debug "Using ID type $ID_TYPE"
            else
                ate_error "Unknown ID type: $OPTARG"
            fi
            ;;
        t)
            if (echo $OPTARG | grep -q "[0-9]\+") ; then
                TIMEOUT=$OPTARG
                ate_debug "Timeout set to $TIMEOUT"
            else
                ate_error "Invalid timeout: $OPTARG"
            fi
            ;;
        n)
            NAME=$OPTARG
            ate_debug "Name set to $NAME"
            ;;
        k)
            KPARAM=$OPTARG
            ate_debug "Default kernel parameter: $KPARAM"
            ;;
        m)
            KPARAM_MIN=$OPTARG
            ate_debug "Kernel parameter for minimal boot: $KPARAM_MIN"
            ;;
        f)
            DUMPTOFILE=$OPTARG
            ate_debug "Dumping commands to executable file"
            echo "#!/bin/sh" > $DUMPTOFILE
            chmod 755 $DUMPTOFILE
            ;;
        d)
            DRY_RUN='1'
            ate_debug "Dry run!"
            ;;
        v)
            VERBOSE='1'
            ate_debug "Verbose mode!"
            ;;
        h)
            print_help
            exit 0
            ;;
        \?)
            print_help
            exit 1
            ;;
    esac
done

# Get name of OS, if unset
if [ "x$NAME" = "x" ] ; then
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        ate_debug "Read name from /etc/os-release: $NAME"
    elif (which lsb_release >/dev/null 2>&1); then
        NAME=$(lsb_release --description --short)
        ate_debug "Read name from 'lsb_release --description --short': $NAME"
    elif [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        NAME=$DISTRIB_DESCRIPTION
        ate_debug "Read name from /etc/lsb-release: $NAME"
    else
        NAME=$(uname -o)
        ate_debug "Read name from 'uname -o': $NAME"
    fi
fi

# Find root file system
if [ "x$ROOT_DEV" = "x" ] ; then
    ROOT_DEV=`findmnt --output SOURCE --noheadings /`
    ate_debug "Root device not set. Using $ROOT_DEV as root device since it's mounted at /."
fi

ROOT_TYPE=`lsblk --nodeps --noheadings --output TYPE $ROOT_DEV`
ate_debug "Root device has type $ROOT_TYPE."
ROOT_PATH=`lsblk --nodeps --noheadings --paths --output NAME $ROOT_DEV`
ate_debug "Root device is on $ROOT_PATH."
if [ "x$ID_TYPE" != "x" ] ; then
    ROOT_ID=`lsblk --nodeps --noheadings --output $ID_TYPE $ROOT_DEV`
    ate_debug "Root device has ID $ROOT_ID."
fi

case $ROOT_TYPE in
    "part")
        if [ "x$ID_TYPE" = "x" ] ; then
            ate_print "Root is on $ROOT_PATH"
            ROOTOPT="root=$ROOT_PATH"
        else
            ate_print "Root is on $ID_TYPE=$ROOT_ID ($ROOT_PATH)"
            ROOTOPT="root=$ID_TYPE=$ROOT_ID"
        fi
        ;;
    "crypt")
        REAL_DEV=`lsblk --inverse --list --noheadings --output NAME --paths $ROOT_PATH | sed -n 2p`

        if [ "x$ID_TYPE" = "x" ] ; then
            ate_print "Root is on $ROOT_PATH wich is encrypted on $REAL_DEV"
            ROOTOPT="root=$ROOT_PATH cryptdevice=$REAL_DEV:`basename $ROOT_PATH`"
        else
            REAL_ID=`lsblk --nodeps --noheadings --output $ID_TYPE $REAL_DEV`
            ate_print "Root is on $ROOT_PATH wich is encrypted on $ID_TYPE=$REAL_ID ($REAL_DEV)"
            ROOTOPT="root=$ROOT_PATH cryptdevice=$ID_TYPE=$REAL_ID:`basename $ROOT_PATH`"
        fi
        ;;
    *)
        ate_error "Root partition has unknown type $ROOT_TYPE!"
        ;;
esac

# Find ESP
if [ "x$ESP" = "x" ] ; then
    ESP=`lsblk --list --paths --output NAME,PARTTYPE --noheadings | grep "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | cut -d " " -f 1`
    if [ "x$ESP" = "x" ] ; then
        ate_error "EFI System Partition not found!"
    fi
fi

ESP_DISK=`echo $ESP | sed 's/[0-9]\+$//g'`
ESP_PART=`echo $ESP | grep -o '[0-9]\+$'`
ate_debug "ESP is on disk $ESP_DISK, partition $ESP_PART."

# Find out where ESP is mounted
# The sed thing is a hack to omit bind mounts on subdirs
EFIROOT=`findmnt --source $ESP --noheadings --output TARGET,SOURCE | sed -n "s| \+$ESP$||p"`
if [ "x$EFIROOT" = "x" ] ; then
    ate_error "EFI System Partition ($ESP) not (properly) mounted!"
    exit 1
fi
ate_print "ESP found on $ESP (mounted on $EFIROOT)."

# Macro for creating boot entries
entry() {
    _NAME=$1
    _KERNEL=$2
    shift; shift;
    _OPTIONS=$*
    ate_print "Adding entry..."
    echo "  :::     Name   : $_NAME"
    echo "  :::     Kernel : $_KERNEL"
    echo "  :::     Options: $_OPTIONS"
    ate_exec "echo \"$_OPTIONS\" | iconv -f ascii -t ucs2 | efibootmgr --quiet --create --disk $ESP_DISK --part $ESP_PART --loader \"$_KERNEL\" --label \"$_NAME\" --append-binary-args -"
}

# Remove all boot entries starting with our name
ate_print "Removing old boot entries..."
for bootnum in `efibootmgr | grep "$NAME" | sed 's/^Boot\([0-9A-F]*\).*/\1/g'`; do
    ate_exec "efibootmgr --quiet --bootnum $bootnum --delete-bootnum"
done

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
        ate_debug "Found Intel Microcode!"
        UCODE="initrd=$EROOT/intel-ucode.img "
    fi

    # Add entries for fallback initramfs
    if [ -f $KROOT/initramfs-$KNAME-fallback.img ] ; then
        
        INITRD="initrd=$EROOT/initramfs-$KNAME-fallback.img"

        # Add entry for minimal options, if set
        if [ "x$KPARAM_MIN" != "x" ] ; then
            entry "$NAME ($KVER) (minimal options)" "$EKERNEL" "$ROOTOPT $INITRD $KPARAM_MIN"
        fi
        entry "$NAME ($KVER) (fallback initrd)" "$EKERNEL" "$ROOTOPT $UCODE$INITRD $KPARAM"
    fi

    # Add normal entry for kernel
    if [ -f $KROOT/initramfs-$KNAME.img ] ; then
        
        INITRD="initrd=$EROOT/initramfs-$KNAME.img"
        entry "$NAME ($KVER)" "$EKERNEL" "$ROOTOPT $UCODE$INITRD $KPARAM"
    fi
done

# Set timeout
ate_print "Set timeout to $TIMEOUT seconds..."
ate_exec "efibootmgr --quiet --timeout $TIMEOUT"
