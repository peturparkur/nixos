{
  lib,
  networkTopology ? null,
  ...
}:

{
  # Add /etc/hosts entries for all nodes in the network topology.
  networking.hosts = lib.mkIf (networkTopology != null) (
    lib.mapAttrs' (name: ip: {
      name = ip;
      value = [
        "${name}.home.arpa"
        "${name}.local" # Retain existing names while consumers migrate from mDNS naming.
      ]
      ++ lib.optionals (name == "amdmini-2") [
        "cache.home.arpa"
        "attic.home.arpa"
      ];
    }) networkTopology
  );
}
