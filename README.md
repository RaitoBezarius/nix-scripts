# nix-scripts

Scripts around Nix/NixOS/NixOps.

## List of scripts

- Auto-install script: just execute the derived script, nice pattern for remote machines with serial console: `curl -F'file=@./result/bin/justdoit' https://youfavoritetextuploader.st | sudo bash` on a temporary NixOS environment (kexec or live CD).

## TODO

### Auto-install

- Better passphrase/key support: go for Mandos
- Better way to pass around the configuration
- Better way to send & execute the script
- Support ext4 rather than btrfs
- More customization
- Integrate with netboot images
- Integrate with a nice DX workflow
- Make a magic website to just do "curl https://clbin.com/something | sudo bash" which would redirect to "curl https://config.nixos.raitobezarius.xyz/generate?stuff | sudo bash"
- Think more on how to handle secrets securely (Vault provisioning, etc.)
