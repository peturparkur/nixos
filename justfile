# rebuild system
nixrebuild:
    sudo nixos-rebuild switch --flake .
nixreboot:
    sudo nixos-rebuild boot --flake .

# update nix packages
update:
    nix flake update
