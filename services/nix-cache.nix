{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:
let
  serverIp = networkTopology.${config.networking.hostName};
  dataDir = "/mnt/data/nix-cache";
  proxyDir = "${dataDir}/nginx";
  atticDir = "${dataDir}/attic";

  upstreamLocation = ttl: {
    proxyPass = "https://cache.nixos.org";
    # The normal reverse-proxy defaults forward the client's Host header.
    recommendedProxySettings = false;
    extraConfig = ''
      proxy_set_header Host cache.nixos.org;
      proxy_ssl_server_name on;
      proxy_ssl_name cache.nixos.org;
      proxy_ssl_verify on;
      # Allow the cross-signed intermediate chain served by cache.nixos.org.
      proxy_ssl_verify_depth 3;
      proxy_ssl_trusted_certificate ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt;

      proxy_cache nix_upstream;
      proxy_cache_valid 200 ${ttl};
      proxy_ignore_headers Cache-Control Expires;
      proxy_cache_lock on;
      proxy_cache_lock_timeout 300s;
      proxy_cache_lock_age 300s;
      proxy_read_timeout 300s;
      add_header X-Cache-Status $upstream_cache_status always;
    '';
  };
in
{
  # Provision this encrypted value before switching; see README.md#shared-nix-cache.
  sops.secrets."nix-cache/attic-env".restartUnits = [ "atticd.service" ];

  # Static ownership is needed for Attic's state outside its StateDirectory.
  users.groups.atticd = { };
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${proxyDir} 0750 ${config.services.nginx.user} ${config.services.nginx.group} -"
    "d ${atticDir} 0700 atticd atticd -"
    "d ${atticDir}/storage 0700 atticd atticd -"
  ];

  services.nginx = {
    enable = true;

    # proxyCachePath always uses /var/cache/nginx; declare the NVMe path directly.
    # max_size is an asynchronous eviction target, not a reservation/hard quota.
    appendHttpConfig = ''
      proxy_cache_path ${proxyDir}
        levels=1:2 keys_zone=nix_upstream:64m
        max_size=50g inactive=30d use_temp_path=off;
    '';

    virtualHosts = {
      "cache.home.arpa" = {
        listenAddresses = [ serverIp ];
        # Upstream signatures authenticate these public downloads; no tokens here.
        locations = {
          "= /nix-cache-info" = upstreamLocation "5m";
          "~ ^/[a-z0-9]+\\.narinfo$" = upstreamLocation "1h";
          "^~ /nar/" = upstreamLocation "30d";
          "/".return = "404";
        };
      };

      "attic.home.arpa" = {
        listenAddresses = [ serverIp ];
        # LAN-only HTTP: upload tokens are not encrypted in transit.
        extraConfig = ''
          client_max_body_size 0;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8081";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_request_buffering off;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
          '';
        };
      };
    };
  };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets."nix-cache/attic-env".path;
    settings = {
      listen = "127.0.0.1:8081";
      allowed-hosts = [ "attic.home.arpa" ];
      api-endpoint = "http://attic.home.arpa/";
      database.url = "sqlite://${atticDir}/server.db?mode=rwc";
      storage = {
        type = "local";
        path = "${atticDir}/storage";
      };
      # Attic has no byte-budget setting. Hard limits require filesystem quotas.
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "90 days";
      };
    };
  };

  # Do not start on the root filesystem if the data NVMe is unavailable.
  systemd.services.nginx = {
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    serviceConfig.ReadWritePaths = [ proxyDir ];
  };
  systemd.services.atticd = {
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      ReadWritePaths = [ atticDir ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}
