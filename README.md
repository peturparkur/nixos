# Personal NixOS configurations

This repository is the Nix flake for my personal x86_64 laptop and a three-node home cluster. The flake defines four NixOS configurations: `peter-laptop`, `amdmini-1`, `amdmini-2`, and `elitedesk800`.

## Hosts

| Flake target | LAN address | Configuration | Role |
|---|---|---|---|
| `peter-laptop` | DHCP | [`nodes/laptop/`](nodes/laptop/) | Personal workstation: Hyprland (default session), GNOME fallback, NVIDIA/AMD graphics, development tools, gaming, VPN, and Syncthing. |
| `amdmini-1` | `192.168.1.45` | [`nodes/amdmini-1/`](nodes/amdmini-1/) | Cluster node running the shared K3s and NATS configuration, plus Garage. |
| `amdmini-2` | `192.168.1.50` | [`nodes/amdmini-2/`](nodes/amdmini-2/) | Cluster node running K3s and NATS, Garage, and still-configured Garage- and Backblaze-backed ZeroFS services (no longer used as filesystems). |
| `elitedesk800` | `192.168.1.30` | [`nodes/elitedesk800/`](nodes/elitedesk800/) | Cluster node running the shared K3s and NATS configuration. |

The cluster's addresses, legacy Garage bootstrap peer entries, and per-node module composition are defined in [`flake.nix`](flake.nix). The laptop uses NetworkManager/DHCP; cluster node addresses are statically assigned there via each node's `default.nix`. Per-machine disk, boot, and hardware settings live in each directory's `hardware.nix`.

## Where to look

- **Flake outputs and shared modules:** [`flake.nix`](flake.nix) defines `nixosConfigurations`, the shared `baseModules`, the cluster-only `nodeModules`, and host-specific additions.
- **Common OS baseline:** [`configuration.nix`](configuration.nix) contains shared system defaults, locale/time zone imports, and command-line tools. [`networking.nix`](networking.nix) adds cluster networking and SSH.
- **Cluster services:** [`kubes/k3s.nix`](kubes/k3s.nix) configures K3s; [`kubes/longhorn.nix`](kubes/longhorn.nix) adds Longhorn prerequisites. [`modules/nats.nix`](modules/nats.nix) configures the NATS cluster.
- **Object and network storage:** [`modules/garage.nix`](modules/garage.nix) configures Garage. [`modules/zerofs.nix`](modules/zerofs.nix) defines the ZeroFS service module, with instance settings in [`services/zerofs.nix`](services/zerofs.nix) and [`services/zerofs_backblaze.nix`](services/zerofs_backblaze.nix). [`modules/virtual-filesystem.nix`](modules/virtual-filesystem.nix) defines NFS/9P mounts; their mount definitions are in [`flake.nix`](flake.nix). See the storage status below for current usage.
- **Laptop desktop and hardware:** [`nodes/laptop/default.nix`](nodes/laptop/default.nix) assembles the laptop's desktop, networking, VPN, sync, and workstation modules. Relevant module definitions include [`modules/gnome_desktop.nix`](modules/gnome_desktop.nix), [`modules/hyprland.nix`](modules/hyprland.nix), [`modules/nvidia.nix`](modules/nvidia.nix), and [`modules/programming_languages.nix`](modules/programming_languages.nix).
- **User environment:** [`users/peter/`](users/peter/) defines the account and shell; [`home/peter/home.nix`](home/peter/home.nix) and [`home/peter/programs/`](home/peter/programs/) hold Home Manager settings. Shell dotfiles are in [`home/dotfiles/`](home/dotfiles/).
- **Packages and reusable services:** [`pkgs/`](pkgs/) contains package/service modules, while [`services/`](services/) contains service configurations.
- **Secrets:** encrypted values are in [`secrets/secrets.yaml`](secrets/secrets.yaml); host age-key recipients and SOPS rules are in [`.sops.yaml`](.sops.yaml). Shared SOPS setup is in [`flake.nix`](flake.nix).

## Storage status and planned migration

### Garage

Garage currently runs in two separate deployments:

- **Native NixOS services:** [`modules/garage.nix`](modules/garage.nix) is enabled on `amdmini-1` and `amdmini-2` only. `elitedesk800` is not configured as a native Garage node. Peers are connected manually by SSHing into the nodes and using the `garage` CLI. The `garageNodes` / `bootstrap_peers` definitions remain from an older attempt at automatic peering and are outdated; they are not the current setup procedure.
- **K3s deployment:** a separate Garage deployment still holds data that needs to be migrated to the native deployment. Its Kubernetes manifests are not defined in this repository.

The planned migration is to move that data to native Garage, then remove the Garage workload from K3s. Kubernetes should retain only Service/load-balancer exposure of the native deployment, with native node IPs centralized in that service definition rather than hardcoded throughout consuming workloads. **This migration is not complete.**

[`docs/deploying-garage.md`](docs/deploying-garage.md) contains useful deployment notes but describes a different three-node setup. Check the current flake and the status above before following it verbatim.

### ZeroFS

The ZeroFS services and mounts remain configured, but `/mnt/zerofs` and `/mnt/backblaze` are no longer used as filesystems: ZeroFS proved too unstable after restarts and/or power cuts for this use.

The retained definitions in [`flake.nix`](flake.nix) configure `/mnt/zerofs` on all four hosts via 9P to `amdmini-2` (`192.168.1.50:5564`), and `/mnt/backblaze` on the laptop via `amdmini-2`'s Tailscale address (`100.73.160.44:5565`). These definitions describe remaining configuration, not recommended or actively used storage.

## Rebuild and update

Run a rebuild on the machine being configured, from this repository:

```sh
sudo nixos-rebuild switch --flake .#$(hostname)
```

The hostname must match one of the flake targets above. The [`justfile`](justfile) provides `just nixrebuild` and `just nixreboot` shortcuts for the current host, plus `just update` to update the pinned inputs in `flake.lock`.

## Secrets

This repository uses [sops-nix](https://github.com/Mic92/sops-nix). The shared configuration expects each host's age private key at `/home/peter/.config/sops/age/keys.txt`; its corresponding public recipient is listed in [`.sops.yaml`](.sops.yaml). The private key must be provisioned separately, not committed to this repository.

With an authorized age key available, edit the encrypted secrets file with:

```sh
nix-shell -p sops --run "sops secrets/secrets.yaml"
```

If a host is added to [`.sops.yaml`](.sops.yaml), or its age key changes, update the recipients for the encrypted file:

```sh
nix-shell -p sops --run "sops updatekeys secrets/secrets.yaml"
```

## Reconfiguring Powerlevel10k

The Home Manager shell setup is in [`home/peter/home.nix`](home/peter/home.nix), and the current prompt configuration is [`home/dotfiles/p10k.zsh`](home/dotfiles/p10k.zsh). To generate a fresh Powerlevel10k configuration:

```zsh
POWERLEVEL9K_CONFIG_FILE=~/new-p10k.zsh p10k configure
```
