{
  config,
  pkgs,
  lib,
  networkTopology,
  ...
}:
let
  # Automatically fetch the IP for the machine currently being evaluated
  hostName = config.networking.hostName;
  myIp = networkTopology.${hostName};

  # Node 1 will be our initial bootstrap master
  initialMasterIp = networkTopology.amdmini-1; # Adjust to your actual master node hostname
  masterName = "ha-redis-master";
  redis_server_name = "ha-redis";
  redis_sentinel_name = "ha-sentinel";
in
{

  # 2. Secret Management
  # Define the sops secret for the Redis password
  sops.secrets."redis/password" = { };

  # CRITICAL: The Redis module stores `masterAuth` in plain text in the Nix store.
  # To keep it completely secret, we use sops-nix templates to inject it at runtime.
  sops.templates."redis-auth.conf" = {
    content = "masterauth ${config.sops.placeholder."redis/password"}";
    owner = config.services.redis.servers.${redis_server_name}.user;
  };

  sops.templates."sentinel-auth.conf" = {
    content = "sentinel auth-pass ${masterName} ${config.sops.placeholder."redis/password"}";
    owner = config.services.redis.servers.${redis_sentinel_name}.user;
  };

  # 3. Redis Data Node (The actual database)
  services.redis.servers.${redis_server_name} = {
    enable = true;
    bind = "127.0.0.1 ${myIp}";
    port = 6379;
    openFirewall = true;

    # Uses the module's secure requirePassFile directive
    requirePassFile = config.sops.secrets."redis/password".path;

    settings = {
      # Securely load the masterauth template
      include = config.sops.templates."redis-auth.conf".path;
      replica-serve-stale-data = "yes";
    };
  };

  # 4. Redis Sentinel Node (The failover manager)
  services.redis.servers.${redis_sentinel_name} = {
    enable = true;
    bind = "127.0.0.1 ${myIp}";
    port = 26379;
    openFirewall = true;
    extraParams = [ "--sentinel" ];

    settings = {
      # Securely load the sentinel auth-pass template
      include = config.sops.templates."sentinel-auth.conf".path;

      # Sentinel quorum configuration
      "sentinel monitor" = "${masterName} ${initialMasterIp} 6379 2";
      "sentinel down-after-milliseconds" = "${masterName} 5000";
      "sentinel failover-timeout" = "${masterName} 10000";
      "sentinel parallel-syncs" = "${masterName} 1";
    };
  };
}
