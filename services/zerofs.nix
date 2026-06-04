{ config, lib, ... }:
{
  services.zerofs = {
    enable = lib.mkDefault false;
    storage.url = "s3://zerofs/zerofs-data";

    servers = {
      nfs.enable = true;
      ninep.enable = true;
      nbd.enable = true;
      rpc.enable = true;
      webui.enable = true;
    };

    aws = {
      endpoint = "http://192.168.1.50:3900";
      region = "garage";
      allowHttp = true;
      conditionalPut = "redis://localhost:6380";
    };

    filesystem = {
      maxSizeGb = 100.0;
      compression = "zstd-11";
    };

    telemetry.enabled = false;

    passwordFile = config.sops.secrets."zerofs/password".path;
    accessKeyIdFile = config.sops.secrets."zerofs/access-key-id".path;
    secretAccessKeyFile = config.sops.secrets."zerofs/secret-access-key".path;
  };

  sops.secrets."zerofs/password" = {
    owner = "zerofs";
    group = "zerofs";
  };
  sops.secrets."zerofs/access-key-id" = {
    owner = "zerofs";
    group = "zerofs";
  };
  sops.secrets."zerofs/secret-access-key" = {
    owner = "zerofs";
    group = "zerofs";
  };
}
