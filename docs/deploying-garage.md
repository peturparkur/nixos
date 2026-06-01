# Deploying Garage S3-Compatible Object Storage on Bare-Metal NixOS Nodes

This document describes the process of deploying [Garage](https://garagehq.deuxfleurs.fr/) — a lightweight, geo-distributed S3-compatible object store — directly onto bare-metal NixOS cluster nodes. It covers why decisions were made, what references were consulted, and the pitfalls encountered along the way.

## Context

We were running Garage inside a k3s (Kubernetes) cluster across 3 nodes. Because Garage is core infrastructure that all other services depend on, we wanted it running bare-metal on the nodes themselves — not inside Kubernetes. This eliminates the k8s dependency layer and ensures Garage starts before and independently of the container orchestration.

Our cluster consists of three NixOS nodes, all sharing a common configuration via a Nix flake:

| Node | IP Address | Notes |
|---|---|---|
| amdmini-1 | 192.168.1.45 | ~1TB SSD storage available |
| amdmini-2 | 192.168.1.50 | ~1TB SSD storage available |
| elitedesk800 | 192.168.1.30 | ~300GB storage (no dedicated SSD) |

## References Consulted

1. **NixOS module source**: [nixos-25.11/nixos/modules/services/web-servers/garage.nix](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/services/web-servers/garage.nix) — The NixOS service module that generates the TOML config and systemd unit. Essential reading to understand what options it exposes, how `DynamicUser` works, and what `settings` keys map to which TOML sections.

2. **Garage configuration reference**: [garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/) — The authoritative list of all TOML config keys, required vs optional fields, and their default values.

3. **Garage cluster deployment guide**: [garagehq.deuxfleurs.fr/documentation/cookbook/real-world/](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/) — Guide for deploying a multi-node cluster, including how to use `bootstrap_peers`, assign layouts with zones, and choose replication factors.

4. **Garage v1 to v2 migration guide**: [garagehq.deuxfleurs.fr/documentation/working-documents/migration-2/](https://garagehq.deuxfleurs.fr/documentation/working-documents/migration-2/) — Breaking changes between v1.x and v2.0, primarily the admin API rework and `replication_mode` → `replication_factor`.

6. **Garage v2.0.0 release notes**: [git.deuxfleurs.fr/Deuxfleurs/garage/releases/tag/v2.0.0](https://git.deuxfleurs.fr/Deuxfleurs/garage/releases/tag/v2.0.0) — Full changelog for v2.0.0 including new features like multiple admin tokens, key expiration, and web redirect support.

7. **Garage reverse proxy guide**: [garagehq.deuxfleurs.fr/documentation/cookbook/reverse-proxy/](https://garagehq.deuxfleurs.fr/documentation/cookbook/reverse-proxy/) — Documentation on configuring reverse proxies (nginx, traefik, etc.) in front of Garage, including required headers and body size settings.

8. **Cloudflare Tunnel documentation**: [developers.cloudflare.com/cloudflare-one/connections/connect-networks/](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — Reference for configuring Cloudflare Tunnel (cloudflared) to expose internal services.

## Step-by-Step Process

### 1. Determining the NixOS module's capabilities

The NixOS `services.garage` module ([source](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/services/web-servers/garage.nix)) generates a TOML config from `services.garage.settings` and creates a systemd service. Key things we learned from reading it:

- It uses `DynamicUser = true` by default — systemd creates a transient user at runtime. This is problematic when you need fixed directory ownership on persistent storage paths.
- It sets `StateDirectory = garage` which handles `/var/lib/garage`, but only that prefix.
- The `package` option must be set explicitly. Without `package = pkgs.garage_2;`, the module doesn't provide a default package.
- The `settings` attrset is a freeform TOML type — you can nest keys like `s3_api.api_bind_addr` and they map to TOML sections like `[s3_api]`.

### 2. Deriving per-node configuration from the network topology

Our flake already defines a `networkTopology` map of node hostnames to IPs. We pass it as a `specialArgs` to each node's NixOS configuration:

```nix
networkTopology = {
  elitedesk800 = "192.168.1.30";
  amdmini-1 = "192.168.1.45";
  amdmini-2 = "192.168.1.50";
};
```

Initially, our bootstrap peers were built from just IPs: `"${ip}:3901"`. This didn't work because Garage v2 requires the full node identifier in `bootstrap_peers`, not just `ip:port`. We now maintain a separate `garageNodes` map that maps node hostnames to their 64-character public keys (obtained from `garage node id`):

```nix
garageNodes = {
  elitedesk800 = "<64-char-public-key>";
  amdmini-1 = "<64-char-public-key>";
  amdmini-2 = "<64-char-public-key>";
};
```

The bootstrap peers are then constructed as `<pubkey>@<ip>:3901`:

```nix
let
  nodeIp = networkTopology.${config.networking.hostName};
  otherNodeNames = lib.filter (name: name != config.networking.hostName)
    (lib.attrNames garageNodes);
  bootstrapPeers =
    map (name: "${garageNodes.${name}}@${networkTopology.${name}}:3901")
    otherNodeNames;
in
```

Both `networkTopology` and `garageNodes` are passed via `specialArgs` in the flake.

### 3. Choosing replication factor and compression

We chose **replication_factor = 2** (not 3) because our storage is asymmetrical:

- amdmini-1 and amdmini-2 each have ~1TB on dedicated SSDs
- elitedesk800 has only ~300GB and no dedicated storage

With replication_factor=3, every object is stored on all 3 nodes, meaning the cluster's usable capacity is limited to the smallest node (300GB). With replication_factor=2, each object lives on 2 nodes, giving us roughly 600GB of usable space while still surviving any single node failure.

We chose **compression_level = 12** (zstd) as a compromise between storage savings and write performance. Per the Garage docs:

- Level 1 is the default — fast but minimal compression
- Levels 10-12 are the sweet spot — similar compression ratios to level 19 but 5-10x faster on writes
- Levels 19-22 give diminishing returns at much higher CPU cost
- **Decompression is always fast** regardless of level (~5-7 GB/s), so read performance is never affected by compression level choice
- The level can be changed at any time — it only affects new uploads, existing blocks keep their original compression

Changing the replication factor after data exists is possible but dangerous — it requires shutting down the entire cluster, deleting `cluster_layout` files from all metadata directories, changing the config, and recreating a layout from scratch with a full rebalance. Set it correctly before writing data.

### 4. Choosing Garage v2 over v1

We initially deployed Garage v1.3.1 (via `pkgs.garage`), but chose to upgrade to v2.x (via `pkgs.garage_2`) before writing any data. Key differences in v2:

- **Admin API v2** — endpoints reworked from `/v1/` to `/v2/` with unambiguous routing
- **`replication_mode` removed** — replaced by `replication_factor` + `consistency_mode`
- **Multiple admin API tokens** — scoped permissions and expiration dates
- **Access key expiration** — S3 keys can now have expiry dates
- **Website redirects** — S3 web endpoint supports redirect rules
- **`garage json-api` command** — JSON-formatted admin API for scripting
- **CLI rework** — CLI now uses RPC internally instead of HTTP
- **CRC64NVME checksumming** — additional checksum algorithm
- **Logging to journald** — native systemd journal support

Since we had no data, the upgrade was simply a `package` change from `pkgs.garage` to `pkgs.garage_2`. For existing clusters, the migration guide requires a controlled shutdown and restart of all nodes simultaneously.

The only config change was `replication_mode` → `replication_factor`, which we were already using.

### 5. Replace DynamicUser with a static user

The NixOS module defaults to `DynamicUser = true`. This creates a transient user with a random UID each time the service starts. For our setup this was problematic because:

1. The data directory (`/mnt/data/garage`) is on persistent storage and needs stable ownership
2. The metadata directory needs consistent UID/GID across service restarts
3. The sops-nix secret file needs to be owned by the service user

We override the systemd unit and declare a static system user:

```nix
users.users.garage = {
  isSystemUser = true;
  group = "garage";
  home = "/var/lib/garage";
};
users.groups.garage = { };

systemd.services.garage.serviceConfig.DynamicUser = lib.mkForce false;
systemd.services.garage.serviceConfig.User = "garage";
systemd.services.garage.serviceConfig.Group = "garage";
```

Using `lib.mkForce false` overrides the module's default `DynamicUser = true`.

### 6. Auto-creating the data directory

Since our data directory (`/mnt/data/garage`) is outside `/var/lib/garage`, systemd's `StateDirectory` won't create it. We use `systemd.tmpfiles.rules`:

```nix
dataDirPath = "/mnt/data/garage";

systemd.tmpfiles.rules = [ "d ${dataDirPath} 0700 garage garage -" ];
```

This creates the directory at boot with correct ownership if it doesn't exist. The `0700` mode ensures only the garage user can access it.

### 7. Managing secrets with sops-nix

The `rpc_secret` is shared across all nodes and must be identical. We store it in sops and reference it via file path:

```nix
sops.secrets."garage/rpc-secret" = {
  owner = "garage";
  group = "garage";
};
```

The `owner` and `group` fields are critical — without them, sops-nix creates the secret file owned by `root:root` with mode `0400`, which the garage user cannot read. This caused a "Permission denied" error on startup.

**Important**: sops-nix interprets `/` in secret names as nested YAML paths. So the secret key `garage/rpc-secret` must be stored in the encrypted YAML as:

```yaml
garage:
  rpc-secret: <hex-value>
```

Not as a flat key `garage/rpc-secret: <hex-value>`. This was not obvious and caused a build failure.

Generate the RPC secret with:

```bash
openssl rand -hex 32
```

### 8. Required TOML fields that caught us out

Garage has strict TOML parsing and requires certain fields. We hit three errors in sequence:

1. **`s3_api.s3_region`** — Required. We set it to `"garage"`.
2. **`s3_web.bind_addr`** — The key is `bind_addr`, not `address`. The `s3_api` section uses `api_bind_addr` instead. Each section has its own naming convention.
3. **`s3_api.root_domain`** and **`s3_web.root_domain`** — Required by the parser even though the docs describe them as optional. We set them to `".s3.garage"` and `".web.garage"` respectively.

The Garage configuration reference ([link](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)) and the full example config in the deployment guide ([link](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/)) were the authoritative sources for field names and which fields are required.

### 9. Bootstrapping nodes and the `bootstrap_peers` gotcha

This was the most significant hurdle we encountered. The `bootstrap_peers` field in Garage's config requires the **full 64-character node public key**, not just `ip:port`.

Our initial config built `bootstrap_peers` from IPs alone:

```nix
bootstrapPeers = map (ip: "${ip}:3901") otherNodes;
# Produced: ["192.168.1.50:3901", "192.168.1.30:3901"]
```

This resulted in nodes starting up but never discovering each other — each node appeared alone in `garage status`.

**The correct format** is `<64-char-pubkey>@<ip>:<port>`, e.g.:

```
7cb7348542593722a1b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5@192.168.1.50:3901
```

Attempting to use the truncated key (as shown by `garage status`) also fails:

```bash
$ garage node connect 37f26cbac4f1ee7e@192.168.1.50:3901
Error: Failure: Unable to parse or resolve node specification
```

Always use `garage node id` to get the full key, not the short form from `garage status`.

**Workaround for initial deployment**: manually connect nodes once with:

```bash
garage node connect <full-pubkey>@<ip>:3901
```

Once nodes have connected, they persist peer information in their metadata directory, so `bootstrap_peers` is only needed for the very first connection. However, we still maintain it in the config for declarative bootstrapping of new or repaved nodes.

We handle this by maintaining a `garageNodes` map in the flake alongside `networkTopology`:

```nix
garageNodes = {
  elitedesk800 = "<full-64-char-key>";
  amdmini-1 = "<full-64-char-key>";
  amdmini-2 = "<full-64-char-key>";
};
```

Each node's public key is obtained by running `garage node id` on that node after first deployment, then copied into the flake.

### 10. Storage capacity configuration

Garage's `data_dir` can be a simple path or a list of attribute sets with capacity information. We use the list format to declare each data directory's capacity:

```nix
data_dir = lib.mkDefault [{
  path = "/mnt/data/garage";
  capacity = "100G";
}];
```

The `capacity` field is **informational** — it tells Garage how much storage to expect for data distribution decisions, but it does not enforce a hard limit. Garage will continue writing past this limit. To enforce hard limits, use a separate partition or filesystem quota.

This format also supports multiple data directories (see [Multi-HDD support](https://garagehq.deuxfleurs.fr/documentation/operations/multi-hdd/)) and allows per-node overrides via `lib.mkDefault`.

### 11. Integrating into the flake

The module is added to `nodeModules` so it's shared across all 3 cluster nodes:

```nix
nodeModules = baseModules ++ [
  ./kubes/k3s.nix
  ./networking.nix
  ./modules/nats.nix
  ./modules/garage.nix
];
```

Both `networkTopology` and `garageNodes` are passed via `specialArgs`:

```nix
specialArgs = {
  inherit inputs self;
  inherit networkTopology garageNodes;
  nodeName = nodename;
};
```

### 12. Post-deployment: assigning the cluster layout

After all three nodes are running and connected, use the `garage` CLI to assign the layout:

```bash
# Check that all 3 nodes can see each other
garage status

# Assign each node to a zone with its capacity
garage layout assign <node-id-1> -z amdmini-1 -c 1T
garage layout assign <node-id-2> -z amdmini-2 -c 1T
garage layout assign <node-id-3> -z elitedesk800 -c 300G

# Review and apply
garage layout show
garage layout apply
```

Each node gets its own zone name, which ensures Garage distributes the 2 copies of each object across different zones for fault tolerance.

### 13. Administration: local CLI without sudo

By default, the `garage` CLI reads `/etc/garage.toml` which is owned by `root`. To allow non-root administration, we added the `peter` user to the `garage` group and made the config file group-readable:

```nix
environment.etc."garage.toml".group = "garage";
environment.etc."garage.toml".mode = "0640";
users.users.peter.extraGroups = [ "garage" ];
```

This allows running `garage status`, `garage layout assign`, etc. directly without `sudo`.

### 14. Administration: remote CLI via admin API

For remote administration without SSH, we enabled the Garage admin API (port 3903) with an authentication token stored in sops:

```nix
sops.secrets."garage/admin-token" = {
  owner = "garage";
  group = "garage";
};

settings = {
  admin.api_bind_addr = "[::]:3903";
  admin.admin_token_file = config.sops.secrets."garage/admin-token".path;
};
```

Add to `secrets.yaml`:

```yaml
garage:
  rpc-secret: <hex>
  admin-token: <openssl rand -base64 32>
```

From any machine on the LAN (or via a tunnel):

```bash
export GARAGE_HOST=http://192.168.1.45:3903
export GARAGE_TOKEN=<your-admin-token>
garage status
garage layout assign ...
```

**Security note**: port 3903 should never be exposed to the internet. The admin token grants full cluster control. Keep it on the LAN only.

### 15. Exposing the S3 API to the internet

Our setup requires remote S3 access, but our router doesn't support port forwarding. We use Cloudflare Tunnel (cloudflared) to expose the S3 API endpoint.

#### Architecture

```
Internet → Cloudflare CDN → cloudflared (on LAN) → Garage S3 API (port 3900)
```

Only port 3900 (S3 API) is exposed. Port 3901 (RPC) stays LAN-only for inter-node communication. Port 3903 (admin API) stays LAN-only for administration.

#### Cloudflare Tunnel configuration

The tunnel routes S3 traffic to the Garage nodes. A cloudflared config like:

```yaml
tunnel: <tunnel-id>
credentials-file: /path/to/credentials.json

ingress:
  - hostname: s3.yourdomain.com
    service: http://192.168.1.45:3900
  - hostname: "*.s3.yourdomain.com"
    service: http://192.168.1.45:3900
  - service: http_status:404
```

The wildcard `*.s3.yourdomain.com` is needed for vhost-style bucket access (e.g. `mybucket.s3.yourdomain.com`). This requires a wildcard DNS record and a wildcard TLS certificate from Cloudflare.

Update `s3_api.root_domain` in the Garage config to match:

```nix
s3_api.root_domain = ".s3.yourdomain.com";
```

#### Cloudflare upload size limitations

Cloudflare's CDN proxy (L7) enforces upload size limits:

| Plan | Max upload size |
|---|---|
| Free | 100MB |
| Pro | 100MB |
| Business | 200MB |

For large objects, use **multipart uploads** — each part must be under the limit, but the total object size is unbounded. Most S3 clients handle this automatically:

```bash
# aws cli — multipart is automatic for files >8MB
aws s3 cp large-file.tar.gz s3://mybucket/ --part-size 64MB

# rclone — automatic multipart
rclone copy large-file.tar.gz remote:mybucket/ --s3-upload-cutoff 64M --s3-chunk-size 64M
```

Set your part/chunk size to something comfortably under the limit (e.g. 64MB or 80MB). Downloads are not size-limited by Cloudflare.

#### Alternative: L4 TCP tunnel

Cloudflare also supports L4 (TCP) tunneling via `cloudflared access tcp`, which has no upload size limits. However, this requires running `cloudflared` on the client side and using `cloudflared access tcp` as a local proxy — standard S3 clients can't connect directly. This is only suitable for programmatic access where you control the client environment.

#### S3 with JuiceFS

When using Garage as a storage backend for JuiceFS over this cloudflare tunnel, no special multipart configuration is needed. JuiceFS splits files into small chunks (default block size 64KB-4MB) and uploads them as individual S3 objects — each well under the 100MB limit. The metadata store should remain local (SQLite, Badger, etc.), while Garage handles only the data blocks.

This is also why we configured a larger `block_size` of 10MB in Garage — since JuiceFS objects are small anyway, and for larger standalone uploads the 10MB block size reduces metadata overhead by producing fewer files in the data directory:

```nix
block_size = "10M";
```

#### What not to expose

| Port | Service | Expose to internet? |
|---|---|---|
| 3900 | S3 API | Yes — via cloudflared |
| 3901 | RPC | No — inter-node only |
| 3902 | S3 Web | Optional — if you need website hosting |
| 3903 | Admin API | No — LAN only, full cluster control |

## Final Configuration

The resulting module at `modules/garage.nix`:

```nix
{ config, pkgs, lib, networkTopology, garageNodes, ... }:

let
  nodeIp = networkTopology.${config.networking.hostName};
  otherNodeNames = lib.filter (name: name != config.networking.hostName)
    (lib.attrNames garageNodes);
  # peers should be taken from garage CLI output of `garage node id`
  bootstrapPeers =
    map (name: "${garageNodes.${name}}@${networkTopology.${name}}:3901")
    otherNodeNames;
  dataDirPath = "/mnt/data/garage";
in {
  sops.secrets."garage/rpc-secret" = {
    owner = "garage";
    group = "garage";
  };
  sops.secrets."garage/admin-token" = {
    owner = "garage";
    group = "garage";
  };

  users.users.garage = {
    isSystemUser = true;
    group = "garage";
    home = "/var/lib/garage";
  };
  users.groups.garage = { };

  environment.etc."garage.toml".group = "garage";
  environment.etc."garage.toml".mode = "0640";
  users.users.peter.extraGroups = [ "garage" ];

  systemd.tmpfiles.rules = [ "d ${dataDirPath} 0700 garage garage -" ];

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = lib.mkDefault [{
        path = dataDirPath;
        capacity = "100G";
      }];
      replication_factor = 2;
      compression_level = 12;
      block_size = "10M";
      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "${nodeIp}:3901";
      rpc_secret_file = config.sops.secrets."garage/rpc-secret".path;
      bootstrap_peers = bootstrapPeers;
      s3_api.api_bind_addr = "[::]:3900";
      s3_api.s3_region = "garage";
      s3_api.root_domain = ".s3.garage";
      s3_web.bind_addr = "[::]:3902";
      s3_web.root_domain = ".web.garage";
      admin.api_bind_addr = "[::]:3903";
      admin.admin_token_file = config.sops.secrets."garage/admin-token".path;
    };
  };

  systemd.services.garage.serviceConfig.DynamicUser = lib.mkForce false;
  systemd.services.garage.serviceConfig.User = "garage";
  systemd.services.garage.serviceConfig.Group = "garage";
}
```

## Decisions Summary

| Decision | Choice | Reason |
|---|---|---|
| Deployment model | Bare-metal, not k8s | Garage is core infra; remove dependency on k3s |
| Garage version | v2.x (`pkgs.garage_2`) | Latest stable; better admin API, key expiration, redirects |
| User model | Static system user | Persistent data directories need stable ownership |
| Replication factor | 2 | Asymmetric storage; avoids limiting capacity to smallest node |
| Compression level | 12 (zstd) | Good ratio without excessive write CPU cost |
| Data directory | `lib.mkDefault` with capacity | Per-node override possible; declares 100G for layout |
| Bootstrap peers | Full `pubkey@ip:port` format | Required by Garage; `ip:port` alone doesn't work |
| Node public keys | `garageNodes` map in flake | Separate from `networkTopology`; keys obtained post-deployment |
| S3 region | `"garage"` | Required field; arbitrary name for internal use |
| Root domains | `.s3.garage` / `.web.garage` | Required by parser; adjust for actual DNS if exposing externally |
| Admin access | Local: garage group membership; Remote: admin API token on LAN | No sudo needed on nodes; remote admin from LAN without SSH |
| Block size | 10M | Reduces metadata overhead on ext4; small objects unaffected |

## Ports Used

| Port | Service | Purpose | Exposed externally? |
|---|---|---|---|
| 3900 | S3 API | Object storage API (S3-compatible) | Yes — via cloudflared |
| 3901 | RPC | Inter-node communication | No — LAN only |
| 3902 | S3 Web | Static website hosting for buckets | Optional |
| 3903 | Admin API | Cluster administration | No — LAN only |

## Troubleshooting Notes

### Nodes don't discover each other via `bootstrap_peers`

If nodes start but appear alone in `garage status`, check that `bootstrap_peers` contains full `<64-char-pubkey>@<ip>:3901` entries. IP-only entries like `192.168.1.50:3901` are silently ignored by Garage v2. The truncated node IDs from `garage status` are also insufficient — always use `garage node id` for the full key.

Manual workaround:
```bash
garage node connect <full-64-char-pubkey>@<ip>:3901
```

Once connected, nodes persist peer info in metadata, so this is only needed once.

### "Permission denied" on startup

The sops-nix secret file for `rpc-secret` must be readable by the `garage` user. Declare ownership:

```nix
sops.secrets."garage/rpc-secret" = {
  owner = "garage";
  group = "garage";
};
```

Without this, the file is owned by `root:root` with mode `0400`.

### TOML parse errors for missing fields

Garage v2 requires these fields that the docs mark as "optional":
- `s3_api.s3_region`
- `s3_api.root_domain`
- `s3_web.root_domain`

Also note that each TOML section uses different key names: `s3_api` uses `api_bind_addr` while `s3_web` uses `bind_addr`.