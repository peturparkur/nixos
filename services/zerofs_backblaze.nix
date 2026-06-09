{ config, lib, ... }:
{
  services.zerofs.backblaze = {
    enable = lib.mkDefault false;

    redis = {
      enable = true;
      serverName = "zerofs-backblaze";
      port = 6381;
    };

    storage.url = "s3://zerofs-b2/zerofs";

    servers = {
      nfs.enable = true;
      ninep = {
        enable = true;
        addresses = [ "0.0.0.0:5565" ];
      };
      nbd = {
        enable = true;
        addresses = [ "127.0.0.1:10810" ];
      };
      rpc = {
        enable = true;
        addresses = [ "127.0.0.1:7001" ];
      };
      webui = {
        enable = true;
        addresses = [ "0.0.0.0:8081" ];
      };
    };

    aws = {
      endpoint = "https://s3.eu-central-003.backblazeb2.com"; # backblaze b2
      region = "eu-central-003";
      allowHttp = false;
      conditionalPut = "redis://localhost:6381";
    };

    filesystem = {
      maxSizeGb = 10.0;
      compression = "zstd-11"; # usual choices are 3, 5, 11
    };

    telemetry.enabled = false;

    passwordFile = config.sops.secrets."backblaze/password".path;
    accessKeyIdFile = config.sops.secrets."backblaze/access-key-id".path;
    secretAccessKeyFile = config.sops.secrets."backblaze/secret-access-key".path;
  };

  sops.secrets."backblaze/password" = {
    owner = "zerofs";
    group = "zerofs";
  };
  sops.secrets."backblaze/access-key-id" = {
    owner = "zerofs";
    group = "zerofs";
  };
  sops.secrets."backblaze/secret-access-key" = {
    owner = "zerofs";
    group = "zerofs";
  };
}
