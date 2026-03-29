{ config, pkgs, lib, ... }: {
  sops.secrets."garage/rpc-secret" = { };

  services.garage = {
    enable = true;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = "/mnt/storage/garage";
      rpc_bind_addr = "[::]:3901";
      rpc_secret_file = config.sops.secrets."garage/rpc-secret".path;
      s3_api.address = "[::]:3900";
    };
  };

}
