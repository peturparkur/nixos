# Personal NixOS configurations

This repository is the Nix flake for my personal x86_64 laptop and a three-node home cluster. The flake defines four NixOS configurations: `peter-laptop`, `amdmini-1`, `amdmini-2`, and `elitedesk800`.

## Hosts

| Flake target | LAN address | Configuration | Role |
|---|---|---|---|
| `peter-laptop` | DHCP | [`nodes/laptop/`](nodes/laptop/) | Personal workstation: Hyprland (default session), GNOME fallback, NVIDIA/AMD graphics, development tools, gaming, VPN, and Syncthing. |
| `amdmini-1` | `192.168.1.45` | [`nodes/amdmini-1/`](nodes/amdmini-1/) | Cluster node running the shared K3s and NATS configuration, plus Garage. |
| `amdmini-2` | `192.168.1.50` | [`nodes/amdmini-2/`](nodes/amdmini-2/) | Cluster node running K3s and NATS, Garage, and a shared Nix binary cache. |
| `elitedesk800` | `192.168.1.30` | [`nodes/elitedesk800/`](nodes/elitedesk800/) | Cluster node running the shared K3s and NATS configuration. |

The cluster's addresses, legacy Garage bootstrap peer entries, and per-node module composition are defined in [`flake.nix`](flake.nix). The laptop uses NetworkManager/DHCP; cluster node addresses are statically assigned there via each node's `default.nix`. Per-machine disk, boot, and hardware settings live in each directory's `hardware.nix`.

## Where to look

- **Flake outputs and shared modules:** [`flake.nix`](flake.nix) defines `nixosConfigurations`, the shared `baseModules`, the cluster-only `nodeModules`, and host-specific additions.
- **Common OS baseline:** [`configuration.nix`](configuration.nix) contains shared system defaults, locale/time zone imports, and command-line tools. [`networking.nix`](networking.nix) adds cluster networking and SSH.
- **Cluster services:** [`kubes/k3s.nix`](kubes/k3s.nix) configures K3s; [`kubes/longhorn.nix`](kubes/longhorn.nix) adds Longhorn prerequisites. [`modules/nats.nix`](modules/nats.nix) configures the NATS cluster.
- **Shared Nix cache:** [`services/nix-cache.nix`](services/nix-cache.nix) configures the Nginx read-through proxy and Attic server. See [setup and publication](#shared-nix-cache) before deploying.
- **Object and network storage:** [`modules/garage.nix`](modules/garage.nix) configures Garage. [`modules/virtual-filesystem.nix`](modules/virtual-filesystem.nix) is a retained NFS/9P client helper, not currently imported. Home Manager object-store mounts are configured in [`home/peter/programs/rclone.nix`](home/peter/programs/rclone.nix), with NixOS integration in [`modules/rclone-mounts.nix`](modules/rclone-mounts.nix). See [object-store mounts](#object-store-mounts) for provisioning and the storage status below for current usage.
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

## Object-store mounts

[`home/peter/programs/rclone.nix`](home/peter/programs/rclone.nix) defines Peter's
Home Manager rclone remotes and mounts. It is imported by the shared home profile,
so the laptop and cluster nodes receive the same configuration. The initial
`garage:` remote root is mounted at `/mnt/garage`; authorized buckets appear as
subdirectories. To mount one bucket directly there, change `mounts.""` to
`mounts."YOUR_BUCKET"` in that file.

[`modules/rclone-mounts.nix`](modules/rclone-mounts.nix) supplies NixOS integration
for enabled Home Manager rclone mounts: persistent mountpoint directories, FUSE
access, user lingering (start without login), and service restart/cleanup settings.
It does not run rclone as root. Native Home Manager options remain the source of
truth for remotes, credentials, mount paths, and flags; no custom provider schema
is required.

### Provisioning credentials

Before rebuilding, use the [secrets workflow](#secrets) to populate every entry
declared in [`users/peter/rclone-secrets.nix`](users/peter/rclone-secrets.nix). Each credential pair uses
this shape in `secrets/secrets.yaml` (shown for the native Garage remote):

```yaml
rclone:
  garage:
    access-key-id: YOUR_GARAGE_ACCESS_KEY_ID
    secret-access-key: YOUR_GARAGE_SECRET_ACCESS_KEY
```

Repeat the pair under `garage-k3s` and `backblaze` for the other configured remotes.
This is a **shape to enter through SOPS**, not plaintext to commit. The key must
have read/write permission on the intended Garage buckets. Credentials are
rendered at runtime into Peter's private rclone configuration, not placed in the
Nix store. NixOS SOPS decrypts the credential files with the system's existing key sources
and gives Peter read-only access (`owner = "peter"`, `mode = "0400"`). Home Manager
references these runtime files under `/run/secrets` and renders the rclone config;
it does not need a second user-level SOPS service or a user-readable copy of the
host's private SSH keys. Missing entries prevent secret provisioning; populate
them before switching. Home Manager manages `~/.config/rclone/rclone.conf`, so
migrate any manually maintained remotes into the declarative configuration first.

The endpoint currently uses the native Garage node's LAN hostname. It is neither
a load-balanced endpoint nor automatic failover, and it requires LAN reachability
(or suitable VPN routing). HTTP does not encrypt request metadata or object contents in transit; S3 request
signing is not encryption. Use only a trusted network or configure HTTPS. Merely having
Tailscale enabled does not route this LAN hostname through it.

### Backblaze provider configuration

The Backblaze remote uses rclone's **native B2 backend** (`type = "b2"`). Leave
`endpoint` unset: B2 discovers the service endpoints without an S3 provider or
region setting. Garage remotes continue to use S3.

Use a manually created application key scoped to the intended bucket, with the
required list/read/write capabilities. Grant deletion capabilities only if needed.
The existing SOPS entries are reused: `access-key-id` supplies B2's `account`
(application key ID, not the master account ID), and `secret-access-key` supplies
B2's `key` (the application key value). No credential regeneration is required
merely to switch from S3 to native B2.

The bucket name is used exactly as configured. Both Garage root mounts expose
buckets authorized for their respective keys; the Backblaze mount exposes one
bucket directly. Switching APIs does not require copying the stored objects.
Before switching an active mount, finish pending uploads and stop the old service;
do not discard its write-back cache.

Native B2 defaults to hiding deleted files rather than purging their versions
(`hard_delete = false`). Retained versions consume storage; configure Backblaze
lifecycle rules according to your recovery and retention requirements.

Reference: [rclone native B2 backend](https://rclone.org/b2/).

### Adding another remote or bucket

In `home/peter/programs/rclone.nix`, use the existing `mkMount` helper for each new
mount. The pure helper lives in [`home/lib/rclone-mount.nix`](home/lib/rclone-mount.nix)
and takes an attribute set with `cacheName`, `mountPoint`, and optional
`vfsCacheMaxSize` (default `"10G"`, meaning 10 GiB in rclone). Every mount needs a
distinct `cacheName`, even when multiple mounts access the same bucket.
S3 remotes can also reuse
`s3Defaults` and `s3Secrets`, keeping endpoint/region choices explicit and selecting
a separate credential pair by name. For example, add these attributes alongside
the existing configuration, replacing bucket names. First add the corresponding
credential pairs to the encrypted YAML and append their `rclone/NAME/access-key-id`
and `rclone/NAME/secret-access-key` paths to the list in
`users/peter/rclone-secrets.nix`; that module assigns ownership and permissions.

```nix
programs.rclone.remotes.b2-example = {
  config.type = "b2";
  secrets = {
    account = osConfig.sops.secrets."rclone/b2-example/access-key-id".path;
    key = osConfig.sops.secrets."rclone/b2-example/secret-access-key".path;
  };
  mounts."YOUR_B2_BUCKET" = mkMount {
    cacheName = "b2-example";
    mountPoint = "/mnt/b2-example";
    vfsCacheMaxSize = "25G"; # Optional override; omit for the 10 GiB default.
  };
};

programs.rclone.remotes.garage-other = {
  config = s3Defaults // {
    region = "garage";
    endpoint = "http://YOUR_GARAGE_ENDPOINT:3900";
  };
  secrets = s3Secrets "garage-other";
  mounts."YOUR_OTHER_BUCKET" = mkMount {
    cacheName = "garage-other";
    mountPoint = "/mnt/garage-other";
  };
};
```

In this additional native-B2 remote, `account` is the application key ID and `key` is its application key.
The native B2 backend does not require an S3 endpoint. Grant only the necessary
bucket capabilities. The additional Garage remote can reuse the endpoint with
independent credentials, or override it for another deployment.

Individual flags can also be set through the normal Home Manager options, for
example in a separate NixOS module:

```nix
home-manager.users.peter.programs.rclone.remotes.garage.mounts."".options.read-only = true;
```

Also use read-only backend credentials when that is a security requirement.
Duplicate mountpoints and exact collisions with NixOS
`fileSystems` are rejected rather than silently mounting over them. This
configuration does not migrate existing object data.

### Operation and limitations

For the initial remote-root mount:

```sh
systemctl --user status 'rclone-mount:@garage.service'
journalctl --user -u 'rclone-mount:@garage.service' -f
systemctl --user restart 'rclone-mount:@garage.service'
```

Home Manager names bucket mounts `rclone-mount:BUCKET@REMOTE.service` (slashes in
remote paths become dots). Mounts restart after failure with a 15-second delay
and no start-rate cutoff. The initial readiness timeout is 90 seconds. A backend
outage after mounting can still cause individual operations to fail; retries do
not make the mount continuously available. Directory listings refresh on access
after cache expiration, not through a continuous synchronization process.

Files are presented as Peter-owned, group `peter`, with mode `0660`; directories
use `0770`. FUSE allows other users to reach the mount but kernel permission
checks still apply. These are local, synthesized permissions: all accesses use
the mount's Garage/B2 credentials, not the calling user's identity. While unmounted,
the path is an ordinary local directory; automated consumers should check that it
is mounted before writing.

Each mount has its own persistent local VFS cache. The `cache-dir` flag selects
the cache root, where rclone stores cached reads, pending writes, and associated
metadata in its own subdirectories. The configured `%C/rclone/CACHE_NAME` uses
a **systemd specifier**, not Nix or shell expansion: for a user service, `%C` is
`$XDG_CACHE_HOME` from the user manager, falling back to `$HOME/.cache`. For Peter,
`%C/rclone/backblaze` therefore normally means
`/home/peter/.cache/rclone/backblaze`. Each node stores its own cache on the
filesystem backing that path; it is not automatically placed on `/mnt/data` or
in the remote bucket. A manual rclone command must use a real path, not `%C`.

With `vfs-cache-mode = "full"`, the cache holds reads and buffers writes before
uploading. `vfsCacheMaxSize` defaults to 10 GiB **per mount** and can be overridden
independently. This is an eviction target, not a hard quota; open files and pending
uploads can cause the cache to exceed it. **Pending uploads exist only locally:
never delete or share a write-back cache between mount processes.**
Closing a file does not prove upload completion. Before changing service ownership
or removing a mount, quiesce writers, verify pending uploads have completed, and
stop the old service before starting its replacement.

These mounts preserve ordinary objects; they are not POSIX-coherent shared
filesystems. Concurrent overwrites can lose updates, and multi-request reads can
cross object replacements. Use immutable object names for stable datasets, not
these mounts for databases or live shared working trees.

### Offline startup

The mount services start automatically but **do not gate the user's
`default.target`**. They set `DefaultDependencies = false` to suppress the target's
automatic ordering after its wanted services. Ordering after `basic.target` and
before/conflicting with `shutdown.target` is restored explicitly, preserving
normal setup and shutdown. `Type = "notify"` still reports actual mount readiness
rather than pretending the mount is ready as soon as its process starts.

Without network access, a mount may remain `activating` for up to its 90-second
startup timeout, then be killed, cleaned up, and retried with a 15-second restart
delay. The startup target proceeds without waiting for it. k3s and native Garage
also have no dependency on mount readiness. No new network-online wait is added.
This does not remove other services' existing networking dependencies or make
applications that access an unavailable mount nonblocking.

Explicitly starting a mount with `systemctl --user start` still waits for its
readiness; Home Manager activation can likewise wait when explicitly restarting
a changed service. These operations are distinct from reaching the user startup
target. Before accessing an offline mount path, consumers must check readiness to
avoid writing into the underlying local directory.

### Shutdown and backend outages

These user mounts are not dependencies of k3s or native Garage. The node services
must keep their own state and storage outside these mounts; in particular,
native Garage uses its local storage rather than its own rclone mount. Do not put
k3s/container runtime state, Garage data, Longhorn storage, or the VFS cache on a
remote FUSE mount. Kubernetes workloads deployed outside this repository may
still introduce dependencies through hostPath volumes; review those separately.

On service stop, restart, or user-manager shutdown, `fusermount3 -uz` first lazily
detaches the mount, without waiting for open files to close or for the remote to
be reachable. The cleanup is repeated after rclone exits. Systemd allows **10
seconds per stop phase**, then uses `SIGKILL` for the service's entire control
group if it fails to stop. This avoids the default long graceful-stop wait and
does not wait indefinitely for Garage/B2 uploads. It is not a promise that the
entire machine shuts down in 10 seconds: stop/cleanup phases and other services
have their own timeouts, and kernel/storage failures are outside this policy.

If either Garage deployment or Backblaze is unavailable, reads/writes through the
mount may still pause or fail. The mount's startup timeout/retry policy does not
make k3s or native Garage depend on its readiness. Provider restarts are not tied
to mount restarts, so there is no circular service dependency between Garage and
its client mount.

Fast shutdown prioritizes node availability over completing uploads. Pending
uploads can remain in the persistent cache and be retried when the same mount
starts again. **Do not delete the cache**, and do not assume every in-flight
application write is durable. For a planned shutdown requiring remote durability,
quiesce writers and verify uploads have completed before stopping the mount.

Evaluation-only regression checks (no credentials, network mounts, or rebuild):

```sh
nix eval --offline --impure --json --file tests/rclone-mounts.nix
```

An optional host-side smoke test exercises the configured stop timeout and kill
policy against a temporary user service that deliberately ignores `SIGTERM`:

```sh
tests/rclone-stop-policy.sh
```

It requires a running systemd user manager and creates no mounts or network
connections. It tests process termination, not FUSE behavior, a real provider
outage, or node reboot. The intentionally timed-out dummy service is cleaned up.

A complementary startup test compares ordinary service defaults against the
configured policy, using a dummy `Type=notify` service that never signals ready:

```sh
tests/rclone-startup-policy.sh
```

The ordinary-defaults control must keep its target waiting. With the configured
policy, the test target must reach `active` while its service remains `activating`.
Only temporary runtime units are used; the real default target, mounts, network,
and node services are not changed.

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

This repository uses [sops-nix](https://github.com/Mic92/sops-nix). The shared
configuration declares an age-key file at `/home/peter/.config/sops/age/keys.txt`.
System-level SOPS can also use the SSH host-key identities selected by
`sops.age.sshKeyPaths` and `sops.gnupg.sshKeyPaths`; successful system decryption does
not imply that a user-level SOPS service has access to the same identities. Public
recipients are listed in [`.sops.yaml`](.sops.yaml) and must also be present in the
encrypted file's recipient metadata. Provision private keys separately, never
commit them, and do not copy root-only SSH host keys into user profiles. Rclone
credentials are decrypted by the system with individual files made readable by
Peter, rather than granting the user service access to a host decryption key.

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
