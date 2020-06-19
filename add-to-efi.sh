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

# I don't want do depend on tput, although it's common on most systems
if (which tput >/dev/null 2>&1); then
    _PRINT=" $(tput setaf 2)[EFI]$(tput sgr0)"
    _ERROR=" $(tput setaf 1)[EFI]$(tput sgr0)"
    _DEBUG=" $(tput setaf 3)[EFI]$(tput sgr0)"
    _EXEC=" $(tput setaf 5)[EFI]$(tput sgr0)"
else
    _PRINT=" [EFI]"
    _ERROR=" [EFI]"
    _DEBUG=" [EFI]"
    _EXEC=" [EFI]"
fi

ate_print() {
    echo "$_PRINT $*"
}

ate_error() {
    echo "$_ERROR $*"
    exit 1
}

ate_debug() {
    if [ "$VERBOSE" -gt "0" ]; then
        echo "$_DEBUG $*"
    fi
}

ate_exec() {
    if [ "$VERBOSE" -gt "0" ] || [ "$DRY_RUN" -gt "0" ]; then
        echo "$_EXEC $*"
    fi
    if [ "$DRY_RUN" = "0" ] && [ "x$DUMP_TO_FILE" = "x" ]; then
        eval "$*"
    fi
    if [ "x$DUMP_TO_FILE" != "x" ] && [ -w "$DUMP_TO_FILE" ]; then
        echo "$*" >> "$DUMP_TO_FILE"
    fi
}

print_help() {
    echo "Usage: $0 [-r <partition>] [-e <partition>] [-p (UUID|PARTUUID|LABEL|PARTLABEL)]"
    echo "       [-t <timeout>] [-n <name>] [-k <kernel-param>] [-m <kernel-param>] [-f <file-name>] [-d] [-v] [-h]"
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

# Default options
TIMEOUT=3
DRY_RUN='0'
VERBOSE='0'
DUMP_TO_FILE=''

# Option parsing
while getopts "r:e:p:t:n:k:m:f:dvh" opt; do
    case $opt in
        r)
            if [ -b "$OPTARG" ]; then
                ROOT_DEV=$OPTARG
                ate_debug "Set root partition to $ROOT_DEV"
            else
                ate_error "Invalid root partition: $OPTARG"
            fi
            ;;
        e)
            if [ -b "$OPTARG" ]; then
                ESP=$OPTARG
                ate_debug "Set EFI partition to $ESP"
            else
                ate_error "Invalid EFI partition: $OPTARG"
            fi
            ;;
        p)
            if (echo "UUID PARTUUID LABEL PARTLABEL" | grep -wq "$OPTARG"); then
                ID_TYPE=$OPTARG
                ate_debug "Using ID type $ID_TYPE"
            else
                ate_error "Unknown ID type: $OPTARG"
            fi
            ;;
        t)
            if (echo "$OPTARG" | grep -q "[0-9]\+"); then
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
            KERNEL_PARAM=$OPTARG
            ate_debug "Default kernel parameter: $KERNEL_PARAM"
            ;;
        m)
            KERNEL_PARAM_MIN=$OPTARG
            ate_debug "Kernel parameter for minimal boot: $KERNEL_PARAM_MIN"
            ;;
        f)
            DUMP_TO_FILE=$OPTARG
            ate_debug "Dumping commands to executable file"
            echo "#!/bin/sh" > "$DUMP_TO_FILE"
            chmod 755 "$DUMP_TO_FILE"
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
if [ "x$NAME" = "x" ]; then
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ate_debug "Read name from /etc/os-release: $NAME"
    elif (which lsb_release >/dev/null 2>&1); then
        NAME=$(lsb_release --description --short)
        ate_debug "Read name from 'lsb_release --description --short': $NAME"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        NAME=$DISTRIB_DESCRIPTION
        ate_debug "Read name from /etc/lsb-release: $NAME"
    else
        NAME=$(uname -o)
        ate_debug "Read name from 'uname -o': $NAME"
    fi
fi

# Find root file system
if [ "x$ROOT_DEV" = "x" ]; then
    ROOT_DEV=$(findmnt --output SOURCE --noheadings /)
    ate_debug "Root device not set. Using $ROOT_DEV as root device since it's mounted at /."
fi

ROOT_TYPE=$(lsblk --nodeps --noheadings --output TYPE "$ROOT_DEV")
ate_debug "Root device has type $ROOT_TYPE."
ROOT_PATH=$(lsblk --nodeps --noheadings --paths --output NAME "$ROOT_DEV")
ate_debug "Root device is on $ROOT_PATH."
if [ "x$ID_TYPE" != "x" ]; then
    ROOT_ID=$(lsblk --nodeps --noheadings --output "$ID_TYPE" "$ROOT_DEV")
    ate_debug "Root device has ID $ROOT_ID."
fi

case $ROOT_TYPE in
    "part")
        if [ "x$ID_TYPE" = "x" ]; then
            ate_print "Root is on $ROOT_PATH"
            ROOT_OPT="root=$ROOT_PATH"
        else
            ate_print "Root is on $ID_TYPE=$ROOT_ID ($ROOT_PATH)"
            ROOT_OPT="root=$ID_TYPE=$ROOT_ID"
        fi
        ;;
    "crypt")
        PHYS_DEV=$(lsblk --inverse --list --noheadings --output NAME --paths "$ROOT_PATH" | sed -n 2p)

        if [ "x$ID_TYPE" = "x" ]; then
            ate_print "Root is on $ROOT_PATH wich is encrypted on $PHYS_DEV"
            ROOT_OPT="root=$ROOT_PATH cryptdevice=$PHYS_DEV:$(basename "$ROOT_PATH")"
        else
            PHYS_ID=$(lsblk --nodeps --noheadings --output "$ID_TYPE" "$PHYS_DEV")
            ate_print "Root is on $ROOT_PATH wich is encrypted on $ID_TYPE=$PHYS_ID ($PHYS_DEV)"
            ROOT_OPT="root=$ROOT_PATH cryptdevice=$ID_TYPE=$PHYS_ID:$(basename "$ROOT_PATH")"
        fi
        ;;
    *)
        ate_error "Root partition has unknown type $ROOT_TYPE!"
        ;;
esac

# Find ESP
if [ "x$ESP" = "x" ]; then
    ESP=$(lsblk --list --paths --output NAME,PARTTYPE --noheadings | grep "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | cut -d " " -f 1)
    if [ "x$ESP" = "x" ]; then
        ate_error "EFI System Partition not found!"
    fi
fi

ESP_DISK=$(echo "$ESP" | sed 's/[0-9]\+$//g')
ESP_PART=$(echo "$ESP" | grep -o '[0-9]\+$')
ate_debug "ESP is on disk $ESP_DISK, partition $ESP_PART."

# Find out where ESP is mounted
# The sed thing is a hack to omit bind mounts on subdirs
# like /esp/EFI/arch on /boot
EFI_ROOT=$(findmnt --source "$ESP" --noheadings --output TARGET,SOURCE | sed -n "s| \+$ESP$||p")
if [ "x$EFI_ROOT" = "x" ]; then
    ate_error "EFI System Partition ($ESP) not (properly) mounted!"
    exit 1
fi
ate_print "ESP found on $ESP (mounted on $EFI_ROOT)."

# Remove all boot entries starting with our name
ate_print "Removing old boot entries..."
for BOOTNUM in $(efibootmgr | grep "$NAME" | sed 's/^Boot\([0-9A-F]*\).*/\1/g'); do
    ate_exec "efibootmgr --quiet --bootnum $BOOTNUM --delete-bootnum"
done

# Look for kernels on ESP
KERNEL_PATHS=$(find "$EFI_ROOT" -name "vmlinu[xz]-*" | sort -r)
for KERNEL_PATH in $KERNEL_PATHS; do
    ate_debug "Looking for kernels in $KERNEL_PATH ..."
    
    # Lookup path for initrds
    KERNEL_DIR=$(dirname "$KERNEL_PATH")
    
    # initrd name depends on kernel name
    KERNEL_NAME=$(basename "$KERNEL_PATH" | sed 's/vmlinu[xz]-//g')

    # Add to entry name later
    KERNEL_VERSION=$(file -b "$KERNEL_PATH" | sed 's/.*version \([^ ]*\).*/\1/g')
    
    # Kernel path seen by EFI
    EFI_KERNEL_PATH=$(echo "$KERNEL_PATH" | sed "s|^$EFI_ROOT||g")

    # ROOT for initrd files seen by EFI
    EFI_KERNEL_DIR=$(echo "$KERNEL_DIR" | sed "s|^$EFI_ROOT||g")

    # Add Intel ucode
    if [ -f "$KERNEL_DIR/intel-ucode.img" ]; then
        ate_debug "Found Intel Microcode!"
        UCODE="initrd=$EFI_KERNEL_DIR/intel-ucode.img "
    fi

    # Add entries for fallback initramfs
    INITRD_NAME="initramfs-$KERNEL_NAME-fallback.img"
    if [ -f "$KERNEL_DIR/$INITRD_NAME" ]; then
        INITRD="initrd=$EFI_KERNEL_DIR/$INITRD_NAME"
        
        if [ "x$KERNEL_PARAM_MIN" != "x" ]; then
            # Add entry for minimal options, if set
            entry "$NAME ($KERNEL_VERSION) (minimal options)" "$EFI_KERNEL_PATH" "$ROOT_OPT $INITRD $KERNEL_PARAM_MIN"
        fi
        entry "$NAME ($KERNEL_VERSION) (fallback initrd)" "$EFI_KERNEL_PATH" "$ROOT_OPT $UCODE$INITRD $KERNEL_PARAM"
    fi

    # Add normal entry for kernel
    INITRD_NAME="initramfs-$KERNEL_NAME.img"
    if [ -f "$KERNEL_DIR/$INITRD_NAME" ]; then
        INITRD="initrd=$EFI_KERNEL_DIR/$INITRD_NAME"
        entry "$NAME ($KERNEL_VERSION)" "$EFI_KERNEL_PATH" "$ROOT_OPT $UCODE$INITRD $KERNEL_PARAM"
    fi
done

# Set timeout
ate_print "Set timeout to $TIMEOUT seconds..."
ate_exec "efibootmgr --quiet --timeout $TIMEOUT"
