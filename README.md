# Personal NixOS configurations

This repository is the Nix flake for my personal x86_64 laptop and a three-node home cluster. The flake defines four NixOS configurations: `peter-laptop`, `amdmini-1`, `amdmini-2`, and `elitedesk800`.

## Hosts

| Flake target | LAN address | Configuration | Role |
|---|---|---|---|
| `peter-laptop` | DHCP | [`nodes/laptop/`](nodes/laptop/) | Personal workstation: Hyprland (default session), GNOME fallback, NVIDIA/AMD graphics, development tools, gaming, VPN, and Syncthing. |
| `amdmini-1` | `192.168.1.45` | [`nodes/amdmini-1/`](nodes/amdmini-1/) | Cluster node running the shared K3s and NATS configuration, plus Garage. |
| `amdmini-2` | `192.168.1.50` | [`nodes/amdmini-2/`](nodes/amdmini-2/) | Cluster node running K3s and NATS, Garage, a shared Nix binary cache, and still-configured Garage- and Backblaze-backed ZeroFS services (no longer used as filesystems). |
| `elitedesk800` | `192.168.1.30` | [`nodes/elitedesk800/`](nodes/elitedesk800/) | Cluster node running the shared K3s and NATS configuration. |

The cluster's addresses, legacy Garage bootstrap peer entries, and per-node module composition are defined in [`flake.nix`](flake.nix). The laptop uses NetworkManager/DHCP; cluster node addresses are statically assigned there via each node's `default.nix`. Per-machine disk, boot, and hardware settings live in each directory's `hardware.nix`.

## Where to look

- **Flake outputs and shared modules:** [`flake.nix`](flake.nix) defines `nixosConfigurations`, the shared `baseModules`, the cluster-only `nodeModules`, and host-specific additions.
- **Common OS baseline:** [`configuration.nix`](configuration.nix) contains shared system defaults, locale/time zone imports, and command-line tools. [`networking.nix`](networking.nix) adds cluster networking and SSH.
- **Cluster services:** [`kubes/k3s.nix`](kubes/k3s.nix) configures K3s; [`kubes/longhorn.nix`](kubes/longhorn.nix) adds Longhorn prerequisites. [`modules/nats.nix`](modules/nats.nix) configures the NATS cluster.
- **Shared Nix cache:** [`services/nix-cache.nix`](services/nix-cache.nix) configures the Nginx read-through proxy and Attic server. See [setup and publication](#shared-nix-cache) before deploying.
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

## Shared Nix cache

[`services/nix-cache.nix`](services/nix-cache.nix), imported by `amdmini-2`, configures two independent caches on its data NVMe:

| Endpoint | Purpose | Data |
|---|---|---|
| `http://cache.home.arpa` | Nginx read-through cache for `https://cache.nixos.org` | `/mnt/data/nix-cache/nginx` |
| `http://attic.home.arpa/home` | Attic cache for explicitly uploaded builds, after provisioning `home` | `/mnt/data/nix-cache/attic` |

The aliases are distributed through [`modules/network-hosts.nix`](modules/network-hosts.nix). Existing `.local` names are retained for compatibility; new names use the reserved `home.arpa` domain. Both frontends bind to the server's LAN address; Attic itself listens only on loopback. The cluster firewall is currently disabled: the declared firewall ports are not an access-control boundary. Do not expose these endpoints to the Internet without reviewing access controls.

Both frontends use HTTP to avoid maintaining local TLS certificates. Nix still verifies package signatures, but HTTP does not encrypt package contents or authenticate the server connection. Attic upload tokens can be captured and replayed by an attacker able to observe or intercept LAN traffic; a stolen upload token can publish packages signed by Attic. Use this only on a trusted LAN, issue narrowly scoped tokens, and never expose it to the Internet. Nginx still uses verified HTTPS when fetching from cache.nixos.org. The services require `/mnt/data` to be mounted, and their service sandboxes allow writes to their respective data directories.

### Provisioning the server

Before switching to this configuration, add the following value to the existing SOPS-encrypted `secrets/secrets.yaml`, using the [secrets workflow](#secrets):

```yaml
nix-cache:
  attic-env: |
    ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="GENERATED_BASE64_RSA_KEY"
```

This is a **plaintext shape to enter through SOPS**, not a value to commit unencrypted. The RSA key in `attic-env` is generated once with `openssl genrsa -traditional 4096 | base64 -w0`. Keep the complete result on one environment-file line. This JWT authentication key is separate from Attic's per-cache package-signing keys, which Attic generates and stores in its database.

The module declares the SOPS secret but does not generate its value or modify the encrypted file. A switch will fail until the value has been provisioned. It also does not automatically create the named Attic cache. Clients only enable the Attic substituter after its public signing key is configured.

After deploying the server, generate a short-lived bootstrap token on the server. Run the wrapper from `/` as shown: it runs as `atticd` and otherwise warns when trying to enter a private working directory under `/home/peter`. No home-directory permission changes are needed:

```sh
(cd / && sudo atticd-atticadm make-token \
  --sub bootstrap --validity 1d \
  --create-cache home --configure-cache home --pull home --push home)
```

Treat the output as a secret. In a shell with `attic` available, log in with that token and create a cache that allows unauthenticated reads within your private network:

```sh
read -r -s -p 'Bootstrap token: ' ATTIC_TOKEN; printf '\n'
attic login local http://attic.home.arpa/ "$ATTIC_TOKEN"
unset ATTIC_TOKEN
attic cache create local:home --public --priority 20
attic cache info local:home
```

Attic stores login credentials in the invoking user's configuration. Put the reported public signing key in the shared client module as described below. Generate scoped upload tokens on the server for regular use, replacing the bootstrap token:

```sh
(cd / && sudo atticd-atticadm make-token \
  --sub laptop --validity 1y --pull home --push home)
```

Prefer a separate token per uploader; tokens need replacing before they expire. Back up the SOPS-encrypted secrets and Attic's database together with its stored objects. For SQLite, stop Attic during a filesystem copy or use a SQLite-aware consistent backup; do not copy a live database without its transactional state.

### Configuring clients

[`modules/nix-cache-client.nix`](modules/nix-cache-client.nix) is imported through `baseModules`, so the laptop and all three cluster nodes use the Nginx read-through substituter and have `attic-client` installed. This includes the cache server itself: its Nginx upstream is explicitly `cache.nixos.org`, so there is no recursive request loop.

Once the Attic cache exists, replace `atticPublicKey = null;` in that module with its complete public signing key, for example:

```nix
atticPublicKey = "home:ACTUAL_BASE64_PUBLIC_KEY";
```

This enables the Attic substituter on all four machines together with its trusted public key. Until then, Attic is deliberately omitted from the substituters; the upstream read-through cache works without any new signing key.

This preserves the default `cache.nixos.org` substituter as a direct fallback. Lower priority values are preferred. Trusting Attic's key means trusting packages uploaded by its writers. The shared module sets a default three-second connection timeout so unreachable local endpoints do not cause long waits when the laptop is away from the LAN. Rebuild each client to apply the settings; changing the server alone does not update clients.

### Publishing existing packages

On the laptop or node holding the packages, log in using its scoped upload token:

```sh
read -r -s -p 'Upload token: ' ATTIC_TOKEN; printf '\n'
attic login local http://attic.home.arpa/ "$ATTIC_TOKEN"
unset ATTIC_TOKEN
```

Push a build result or the running NixOS system, including its dependency closure:

```sh
attic push local:home ./result
attic push local:home /run/current-system
```

To publish every currently valid path in the local store, enumerate it with `nix path-info --all` and push bounded batches. This includes derivation and source paths as well as built outputs:

```sh
set -o pipefail
nix path-info --all \
  | xargs -r -d '\n' -n 128 sh -c \
      'attic push local:home --no-closure "$@" || exit 255' attic-batch
```

This uses GNU `xargs` to run one batch at a time, with at most 128 paths per invocation. Each invocation uses Attic's positional-path mode rather than its asynchronous stdin mode. `exit 255` tells `xargs` to stop if any batch fails instead of continuing through the store. A successfully uploaded earlier batch remains available if a later one fails.

`--no-closure` avoids expanding each batch beyond its bound because every currently valid path is already in the full input. The commands do not copy GC roots, profiles, or the Nix store database. They publish package contents; review them for private source and other sensitive data before bulk publication. Avoid running GC during the upload: the enumeration is not an atomic rooted snapshot, and paths can disappear before they are read.

By default Attic skips paths signed by `cache.nixos.org-1`, because they are available upstream. This is usually appropriate here: Nginx caches those packages when clients download them. To also upload those upstream-signed paths into Attic explicitly:

```sh
set -o pipefail
nix path-info --all \
  | xargs -r -d '\n' -n 128 sh -c \
      'attic push local:home --no-closure --ignore-upstream-cache-filter "$@" || exit 255' attic-batch
```

Uploads are deduplicated, so rerunning the commands only transfers missing content. Uploading to Attic does not populate the separate Nginx cache.

If an entire-store push returns `InternalServerError` or `sending into a closed channel`, first try a single unfiltered path without stdin:

```sh
attic push local:home --no-closure --ignore-upstream-cache-filter /run/current-system
```

The closed-channel error is an internal client queue error: a background worker can stop after an earlier failure, and the stdin reader can mask the original error. Large missing-path queries are one possible failure source with SQLite, but the error alone does not establish that cause. A single-path push can reveal the underlying error without the stdin worker; even a successful single-path upload does not prove that its dependencies have been uploaded.

On the server, watch the logs during the attempt:

```sh
sudo journalctl -fu atticd
```

For recent failures, use `sudo journalctl -u atticd --since '15 minutes ago' --no-pager`. Check the actual database/storage error before changing tokens, filesystem permissions, or database settings. `attic cache info` only confirms metadata retrieval; public cache reads do not prove that your upload token has write permission.

### Capacity and cleanup

Nginx has a **50 GiB eviction target**, not a preallocated reservation or hard filesystem quota. It evicts inactive entries after 30 days and manages size asynchronously, so usage can temporarily exceed the target. Leave headroom on the NVMe. The `X-Cache-Status` response header distinguishes `MISS` and `HIT` for repeated requests to the read-through endpoint.

Attic has **no built-in byte-budget option** in the pinned version. This configuration runs its GC every 12 hours, with a default retention of 90 days for objects old enough and not accessed within that period. This does not guarantee a maximum disk size. A hard limit requires an ext4 project quota or a dedicated bounded filesystem; neither is configured here. A hard quota rejects further writes when full rather than automatically evicting old objects. Choose an Attic budget and quota strategy before bulk-uploading a large store.

Client Nix GC, Nginx eviction, and Attic GC are independent. None removes packages from another machine's local store.

### Troubleshooting upstream proxy errors

An HTTP `502` from `cache.home.arpa` means Nginx received the request but could not successfully serve it through its upstream path. Inspect the server logs rather than changing Attic tokens:

```sh
curl -i http://cache.home.arpa/nix-cache-info
sudo journalctl -u nginx --since '10 minutes ago' --no-pager
curl -i https://cache.nixos.org/nix-cache-info
```

For `upstream SSL certificate verify error: (22:certificate chain too long)`, check that the active upstream locations include `proxy_ssl_verify_depth 3;`. The default depth of one is insufficient for the cross-signed certificate chain observed at `cache.nixos.org`. Keep `proxy_ssl_verify on`; increasing the depth does not disable certificate or hostname verification. This concerns Nginx's outbound HTTPS connection, not TLS certificates for your local HTTP endpoints.

To rebuild while bypassing a broken local cache, override both substituter settings for that invocation:

```sh
sudo nixos-rebuild switch --flake .#amdmini-2 \
  --option substituters https://cache.nixos.org \
  --option extra-substituters ''
```

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
