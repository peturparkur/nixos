{
  lib,
  networkTopology,
  nodeName,
  ...
}:
let
  # NATS ports
  clientPort = 4222;
  clusterPort = 6222;
  monitorPort = 8222;

  # Build cluster routes from network topology
  # NATS ignores self-routes automatically
  routes = lib.mapAttrsToList (name: ip: "nats://${ip}:${toString clusterPort}") networkTopology;
in
{
  services.nats = {
    enable = true;
    serverName = nodeName;
    port = clientPort;
    jetstream = true;

    settings = {
      # Listen on all interfaces for client connections
      listen = "0.0.0.0:${toString clientPort}";

      # Enable HTTP monitoring endpoint
      http_port = monitorPort;

      # Cluster configuration for HA
      cluster = {
        name = "nixos-nats-cluster";
        listen = "0.0.0.0:${toString clusterPort}";
        inherit routes;
      };

      # JetStream configuration for persistent messaging
      jetstream = {
        max_mem = "1G";
        max_file = "10G";
      };
    };
  };

  # Ensure firewall allows NATS ports (even if firewall is disabled, this documents the ports)
  networking.firewall.allowedTCPPorts = [
    clientPort
    clusterPort
    monitorPort
  ];
}
