{ pkgs, lib, ... }:
# Taken from cleverca22/nix-tests repository.

with lib;
let
  mkBootTable = {
    ext4 = "mkfs.ext4 $NIXOS_BOOT -L NIXOS_BOOT";
    vfat = "mkfs.vfat $NIXOS_BOOT -n NIXOS_BOOT";
  };
  mkSubvolume = s: "btrfs subvolume create /mnt/${s}";
in { rootDevice ? "/dev/sda", bootSize ? 256, bootType ? "vfat", swapSize ? 1024, rootSubvolumeName ? "nixos", uefi ? true, luksEncrypt ? false, remoteUnlock ? false, nvme ? false, externalConfig ? null, authorizedKeys ? [] }:
  let
    x = if nvme then "p" else "";
  in
  pkgs.writeScriptBin "justdoit" ''
      #!${pkgs.stdenv.shell}

      set -e

      wipefs -a ${rootDevice}
      dd if=/dev/zero of=${rootDevice} bs=512 count=10000
      sfdisk ${rootDevice} <<EOF
      label: gpt
      device: ${rootDevice}
      unit: sectors
      1 : size=${toString (2048 * bootSize)}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
      ${lib.optionalString (! uefi) "4 : size=4096, type=21686148-6449-6E6F-744E-656564454649"}
      2 : size=${toString (2048 * swapSize)}, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
      3 : type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
      EOF
      ${if luksEncrypt then ''
        cryptsetup luksFormat -q -d passphrase ${rootDevice}${x}3
        cryptsetup open -d passphrase --type luks ${rootDevice}${x}3 root

        export ROOT_DEVICE=/dev/mapper/root
      '' else ''
        export ROOT_DEVICE=${rootDevice}${x}3
      ''}
        export NIXOS_BOOT=${rootDevice}${x}1
        export SWAP_DEVICE=${rootDevice}${x}2

        mkdir -p /mnt

        ${mkBootTable.${bootType}}
        mkswap $SWAP_DEVICE -L NIXOS_SWAP
        mkfs.btrfs $ROOT_DEVICE -L NIXOS_ROOT
        mount -t btrfs $ROOT_DEVICE /mnt
        ${mkSubvolume rootSubvolumeName}
        umount /mnt

        swapon $SWAP_DEVICE
        mount -t btrfs -o subvol=${rootSubvolumeName},compress=zstd,noatime $ROOT_DEVICE /mnt/
        ${mkSubvolume "home"}
        ${mkSubvolume "nix"}
        ${mkSubvolume "persist"}
        ${mkSubvolume "root"}
        ${mkSubvolume "log"}
        btrfs subvolume snapshot -r /mnt/root /mnt/root-blank

        mkdir /mnt/boot
        mount $NIXOS_BOOT /mnt/boot

        nixos-generate-config --root /mnt/

        hostId=$(echo $(head -c4 /dev/urandom | od -A none -t x4))
        ${if externalConfig != null then ''
          echo > /mnt/etc/nixos/configuration.nix <<EOF
          ${builtins.readFile (./. + "${externalConfig}")}
          EOF
        '' else ""}
        ${lib.optionalString remoteUnlock ''
          echo "Do not forget to copy the host key in your ~/.ssh/known_hosts."
          nix run nixpkgs.dropbear -c dropbearkey -t ecdsa -f /mnt/persist/host_ecdsa_key
        ''}

        cat > /mnt/etc/nixos/generated.nix <<EOF
        { ... }:
        {
        ${if uefi then ''

        '' else ''
          boot.loader.grub.device = "${rootDevice}";
        ''}

          ${lib.optionalString luksEncrypt ''
            boot.initrd.luks.devices = [
            { name = "root"; device = "${rootDevice}${x}3"; }
            ];
                ${lib.optionalString remoteUnlock ''
                  boot.initrd.network = {
                    enable = true;
                    ssh = { enable = true; port = 22; authorizedKeys = ${generators.toPretty {} authorizedKeys}; hostECDSAKey = /persist/host_ecdsa_key; };
                  };
                  services.openssh.hostKeys = [ { path = "/persist/host_ecdsa_key"; } ];
                  users.users.root.openssh.authorizedKeys = ${generators.toPretty {} authorizedKeys};
                  services.openssh.enable = true;
              ''}
          ''}
            }
      EOF
            nix run nixpkgs.nixfmt -c nixfmt /mnt/etc/nixos/generated.nix /mnt/etc/nixos/configuration.nix

            nixos-install

            umount /mnt/home /mnt/nix /mnt/boot /mnt
            swapoff $SWAP_DEVICE
          ''
