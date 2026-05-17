{ config, pkgs, lib, networkTopology, ... }:

let
  nodeIp = networkTopology.${config.networking.hostName};
  otherNodes = lib.filter (ip: ip != nodeIp) (lib.attrValues networkTopology);
  bootstrapPeers = map (ip: "${ip}:3901") otherNodes;
in {
  sops.secrets."garage/rpc-secret" = { };

  services.garage = {
    enable = true;
    package = pkgs.garage;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = lib.mkDefault "/mnt/storage/garage";
      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "${nodeIp}:3901";
      rpc_secret_file = config.sops.secrets."garage/rpc-secret".path;
      bootstrap_peers = bootstrapPeers;
      s3_api.address = "[::]:3900";
      s3_web.address = "[::]:3902";
    };
  };
}
