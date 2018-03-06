# add-to-efi.sh
This script allows users and administrators to automatically add their EFISTUB-enabled Linux system to the system's native EFI bootloader without the need of any additional bootloader.

It's required that all files needed to perform the boot process (e.g. vmlinuz-xxx, initramfs-xxx.img) reside on the EFI system partition, which has to be mounted *somewhere*.

The tool searches for the EFI partition by its partition type, then for installed kernels and finally for suitable initrds (including Intel Microcode).

Furthermore, the tool is able to detect if the root filesystem is encrypted and adds appropriate kernel parameters.

If you want to use (PART)UUID for booting, this tool will also do.

## Usage

    add-to-efi.sh [-r <partition>] [-e <partition>] [-p <identifier>] [-t <timeout>] [-n <name>] [-k <kernel-param>] [-m <kernel-param>] [-f <filename>] [-d] [-v] [-h]
    
``add-to-efi.sh -r /dev/sda5`` will set the root partition of the system to ``/dev/sda5``. By default, add-to-efi.sh will assume that the filesystem mounted at ``/`` is the root file system.
    
``add-to-efi.sh -e /dev/sda2`` will set the EFI system partition to ``/dev/sda2``. By default, add-to-efi.sh will search for a partition with the partition type ``c12a7328-f81f-11d2-ba4b-00a0c93ec93b``, which is always the EFI system partition. (See https://en.wikipedia.org/wiki/EFI_system_partition)

``add-to-efi.sh -p UUID`` will instruct add-to-efi.sh to use UUID as specifier for the root partition in the kernel parameter. (PART)LABEL and PARTUUID are also supported. If this option is omitted, add-to-efi.sh uses the /dev/sdx-notation.

``add-to-efi.sh -t 5`` sets the bootloader timeout to 5 seconds, which is commonly ignored by EFI bootloaders. It defaults to 3 seconds.

``add-to-efi.sh -n "EpicLinux"`` sets the used OS name to EpicLinux. The bootloader entries follow the scheme: ``<name> (<kernel version>)``, with additional ``(fallback initrd)`` or ``(minimal options)``. If the name is omitted, add-to-efi.sh will probe ``/etc/os-release``, ``lsb_release --description``, ``/etc/lsb-release`` and finally ``uname -o`` in this order. The first information found is taken as name. The kernel version is fetched using ``file <kernel file>``.

``add-to-efi.sh -k rw`` adds ``rw`` to the kernel parameters. There is no need to specify ``initrd``, ``cryptdevice`` and ``root`` here since add-to-efi.sh adds them automatically. 

``add-to-efi.sh -m ro`` adds ``ro`` to the minimal kernel parameters. If set, add-to-efi.sh creates for each kernel with a suitable fallback initrd an additional entry with minimal boot options. Microcode and options specified with ``-k`` are omitted.

``add-to-efi.sh -f run.sh`` instructs add-to-efi.sh not to run the operations on the EFI, but to write the commands that would have been executed to a file called ``run.sh``. This file can be inspected by paranoid users and run later with sudo. This option implies ``-d`` (see below)

``add-to-efi.sh -d`` enables dry run. Critical commands are not executed.

``add-to-efi.sh -v`` enables verbose output. Should be the first option if command parsing has to be debugged.

``add-to-efi.sh -h`` prints help.

## Limitations

Currently, add-to-efi.sh adds all found kernels on the EFI system partition to the bootloader, there is no way to exclude kernels for other installations.

Other device-mapper-enabled options are unsupported, but might be added later.

There is currently no way to specify kernel parameters for specific kernels.

For every kernel named ``vmlinu{x,z}-xxx``, an initrd is considered inherent, if it is named ``initramfs-xxx.img`` or ``initramfs-xxx-fallback.img``. These naming conventions are common on Arch Linux, but support for other naming conventions are non-existent.
