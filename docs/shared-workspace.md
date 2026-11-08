# Shared workspace

[`services/shared-workspace.nix`](../services/shared-workspace.nix) provides a small,
frequently accessed workspace at `/mnt/shared`, separate from the Garage and
Backblaze object-store mounts. `amdmini-1` hosts it locally and exports it over
NFSv4; the other cluster nodes and the laptop mount that export on demand. Normal
Linux client/server RAM caching remains enabled. There is **no replication or
backup** of this workspace; keep important artifacts elsewhere as well.

## Backing storage and disk usage

The files live in `/mnt/data/shared` on amdmini-1's existing data NVMe. That
ordinary directory is bind-mounted at `/mnt/shared`, which is exported over NFS.
The server and clients therefore use the same workspace path, without moving
storage onto the OS disk.

There is **no quota, reservation, eviction policy, or dedicated filesystem**.
The workspace shares free space with Garage and any other data on `/mnt/data`.
It can fill that filesystem and disrupt those services, so monitor available
space and remove unneeded artifacts. No filesystem feature changes or offline
quota provisioning are required.

A preparation service requires `/mnt/data` to be an actual mount before creating
the source directory or applying its root permissions. It rejects a symlinked
source directory and never recursively changes ownership of existing contents.
The bind mount depends on that preparation and the data mount. Before NFS starts,
a readiness check verifies that `/mnt/shared` is mounted and refers to the same
device/inode as `/mnt/data/shared`. Both NFS daemons stop if the workspace or data
mount stops; the export is also conditional on the workspace mount being present.
This prevents silently exporting an ordinary directory on the OS disk when the
data drive is unavailable.

### Earlier image-backed deployments

The previous implementation stored a bounded filesystem image at
`/mnt/data/.shared-workspace/workspace.ext4`. The new configuration does **not**
copy, delete, resize, or otherwise migrate that image. If it exists, preparation
fails closed rather than exposing an empty replacement workspace. An already
mounted image at `/mnt/shared` also fails the directory-identity check.

If the earlier configuration was deployed, quiesce clients and migrate any
workspace data into `/mnt/data/shared` during explicit maintenance before
switching. Preserve ownership and permissions, verify the copy, and retain a
backup before retiring the old image. Remove the legacy image from its old path
only after handling its contents deliberately; do not merely delete it to bypass
the guard. Clients should unmount/remount across that storage replacement rather
than continuing to use file handles from the old filesystem. If the earlier
configuration was never deployed, no migration is needed.

## Access and deployment

The mounted workspace root belongs to Peter's consistent UID/GID, with mode
`2770`; other users do not receive access automatically. Files created remotely
use normal Unix ownership and permission semantics, not rclone's synthesized
permissions. The setgid directory preserves the directory group for new entries.
The server uses its local mount, not an NFS mount of itself.

The export permits the trusted home LAN, uses synchronous exports and root
squashing, and binds the NFS listener to the server's LAN address. It uses
`sec=sys` (numeric Unix identities), **not encryption or cryptographic client
identity**. Root squashing does not protect against a hostile LAN client
impersonating Peter. The cluster firewall is currently disabled; declaring port
2049 is not an access-control boundary. Do not expose this service to the
Internet. No Tailscale subnet routing or off-site connectivity is added.

Rebuild `amdmini-1` first using the [normal workflow](../README.md#rebuild-and-update),
then rebuild each client. Review the migration note above before switching an
existing image-backed deployment. On the server:

```sh
systemctl status shared-workspace-directory.service shared-workspace-ready.service nfs-server.service
findmnt /mnt/shared
df -h /mnt/data
```

The directory preparation and readiness services remain `active (exited)` after
success. Preparation stops with the workspace mount, so the next mount revalidates
its source directory.

On a client, accessing the directory triggers its first connection:

```sh
ls /mnt/shared
findmnt /mnt/shared
```

A file written by Peter on one machine is then accessible to Peter on the others.
Use this for shared files/artifacts, not simultaneous unsynchronized edits to the
same working tree or arbitrary multi-host access to a database.

## Offline operation and outages

Client mounts use `nofail` and systemd automounts: **boot and login do not wait for
the NFS server**, and no connection is made until something accesses the path.
The mount helper has a 10-second timeout, with no additional mount-helper retry
period. An idle mount is eligible for unmounting after 60 seconds; open files,
working directories, or other users of the mount can prevent idle unmounting.
Do not configure login scripts, indexers, or required infrastructure services to
scan `/mnt/shared` when offline. K3s and Garage have no added dependency on it.

This is **not an offline synchronized workspace**. Access while disconnected can
wait for the mount attempt and fail. The helper timeout is not a universal bound
on networking dependencies or every filesystem operation. A later access can
retry when connectivity returns. If repeated attempts hit systemd's start limit:

```sh
sudo systemctl reset-failed mnt-shared.mount
```

Clients deliberately retain NFS's data-safe **`hard`** mode. If a mounted server
disappears during use, outstanding I/O can wait until it returns, and can also
complicate shutdown. An automount/startup timeout does not bound that I/O. `soft`
mounts are not used because returning errors from partially completed operations
can corrupt files. Before taking the laptop offline, close workspace files, leave
any working directory under the mount, and, while the server is still reachable,
optionally stop both units:

```sh
sudo systemctl stop mnt-shared.automount mnt-shared.mount
# Back home, re-enable on-demand access:
sudo systemctl start mnt-shared.automount
```

Keep K3s/container state, Garage data, Longhorn storage, and
object-store VFS caches outside the NFS client mount. Kubernetes workloads defined
elsewhere may introduce dependencies through hostPath volumes; review those
separately.

Run these regression checks from the repository root (no rebuilds, service starts,
network mounts, or changes to server storage):

```sh
nix eval --offline --impure --json --file tests/shared-workspace.nix
tests/shared-workspace-units.sh
```

The unit test uses the installed systemd fstab generator and evaluates the
configured fstab files into temporary units without loading them. These checks do
not replace a post-deployment check of real cross-host reads/writes or an outage.

## References and NixOS conventions

The [NixOS NFS wiki](https://wiki.nixos.org/wiki/NFS) describes server exports,
client filesystem support, lazy mounting, idle disconnection, and firewall ports.
This configuration follows its `fileSystems`/automount approach and bind-mounts
the source directory into the exported path. A separate `/export` hierarchy is
unnecessary for this single share. `fsid=0` makes `/mnt/shared` the NFSv4
root, so clients use `SERVER:/`, not `SERVER:/mnt/shared`.

The pinned NixOS NFS module enables `rpcbind` and supplies NFS mount helpers when
`boot.supportedFilesystems` includes `nfs`. The explicit `vers=4.2` option is an
alias for the wiki's `nfsvers=4.2`; `fsType = "nfs"` is valid for NFSv4, while
`nfs4` is the older filesystem-type spelling. See [nfs(5)](https://man7.org/linux/man-pages/man5/nfs.5.html).
The wiki's multi-export `nohide` option is unnecessary here, and its `insecure`
option is not needed for these privileged system mounts; the default reserved
client-port requirement is retained.
