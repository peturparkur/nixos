{
  config,
  lib,
  networkTopology ? null,
  ...
}:

{
  # Add /etc/hosts entries for all nodes in the network topology
  networking.hosts = lib.mkIf (networkTopology != null) (
    lib.mapAttrs' (name: ip: {
      name = ip;
      value = [ "${name}.local" ];
    }) networkTopology
  );
}
