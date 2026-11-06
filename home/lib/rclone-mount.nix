{ gid }:
{
  cacheName,
  mountPoint,
  vfsCacheMaxSize ? "10G",
}:
{
  enable = true;
  inherit mountPoint;
  options = {
    allow-other = true;
    default-permissions = true;
    inherit gid;
    dir-perms = "0770";
    file-perms = "0660";
    umask = "0007";
    dir-cache-time = "30s";
    vfs-cache-mode = "full";
    # systemd expands %C to the user manager's cache directory at service startup.
    cache-dir = "%C/rclone/${cacheName}";
    vfs-cache-max-size = vfsCacheMaxSize;
  };
}
