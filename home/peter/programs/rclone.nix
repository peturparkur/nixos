{ osConfig, ... }:
let
  s3Defaults = {
    type = "s3";
    provider = "Other";
    force_path_style = true;
  };
  s3Secrets = name: {
    access_key_id = osConfig.sops.secrets."rclone/${name}/access-key-id".path;
    secret_access_key = osConfig.sops.secrets."rclone/${name}/secret-access-key".path;
  };

  mkMount = import ../../lib/rclone-mount.nix {
    gid = osConfig.users.groups.peter.gid;
  };
in
{
  programs.rclone = {
    enable = true;
    remotes.garage = {
      config = s3Defaults // {
        region = "garage";
        endpoint = "http://amdmini-1.home.arpa:3900";
      };
      secrets = s3Secrets "garage";
      # Mount the remote root: authorized buckets appear as subdirectories.
      # Use mounts."bucket-name" instead to expose only that bucket here.
      mounts."" = mkMount {
        cacheName = "garage";
        mountPoint = "/mnt/garage";
      };
    };
    remotes.garagek3s = {
      config = s3Defaults // {
        region = "garage";
        endpoint = "http://192.168.1.169:3900";
      };
      secrets = s3Secrets "garage-k3s";
      # Mount all buckets authorized for this deployment's key.
      mounts."" = mkMount {
        cacheName = "garagek3s";
        mountPoint = "/mnt/garage-k3s";
      };
    };
    remotes.backblaze = {
      config.type = "b2";
      secrets = {
        account = osConfig.sops.secrets."rclone/backblaze/access-key-id".path;
        key = osConfig.sops.secrets."rclone/backblaze/secret-access-key".path;
      };
      # Mount this existing bucket directly; its spelling is intentional.
      mounts."bbackblaze" = mkMount {
        cacheName = "backblaze";
        mountPoint = "/mnt/backblaze";
        vfsCacheMaxSize = "5G";
      };
    };
  };
}
