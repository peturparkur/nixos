{ config, pkgs, lib, networkTopology, ... }:

let
  nodeIp = networkTopology.${config.networking.hostName};
  otherNodes = lib.filter (ip: ip != nodeIp) (lib.attrValues networkTopology);
  bootstrapPeers = map (ip: "${ip}:3901") otherNodes;
in {
  sops.secrets."garage/rpc-secret" = {
    owner = "garage";
    group = "garage";
  };

  users.users.garage = {
    isSystemUser = true;
    group = "garage";
    home = "/var/lib/garage";
  };
  users.groups.garage = { };

  systemd.tmpfiles.rules =
    [ "d ${config.services.garage.settings.data_dir} 0700 garage garage -" ];

  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = lib.mkDefault "/mnt/data/garage";
      replication_factor = 2;
      compression_level = 12;
      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "${nodeIp}:3901";
      rpc_secret_file = config.sops.secrets."garage/rpc-secret".path;
      bootstrap_peers = bootstrapPeers;
      s3_api.api_bind_addr = "[::]:3900";
      s3_api.s3_region = "garage";
      s3_api.root_domain = ".s3.garage";
      s3_web.bind_addr = "[::]:3902";
      s3_web.root_domain = ".web.garage";
    };
  };

  systemd.services.garage.serviceConfig.DynamicUser = lib.mkForce false;
  systemd.services.garage.serviceConfig.User = "garage";
  systemd.services.garage.serviceConfig.Group = "garage";
}
