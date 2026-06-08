{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.zerofs;
  tomlFormat = pkgs.formats.toml { };
  zerofsPkg = pkgs.zerofs;
in
{
  options.services.zerofs = {
    enable = lib.mkEnableOption "ZeroFS distributed filesystem";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zerofs;
      description = "The ZeroFS package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "zerofs";
      description = "User account under which ZeroFS runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "zerofs";
      description = "Group account under which ZeroFS runs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zerofs";
      description = "Data directory for ZeroFS.";
    };

    cache = {
      dir = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.dataDir}/cache";
        description = "Cache directory.";
      };
      diskSizeGb = lib.mkOption {
        type = lib.types.number;
        default = 1.0;
        description = "Disk cache size in GB.";
      };
      memorySizeGb = lib.mkOption {
        type = lib.types.number;
        default = 2.0;
        description = "Memory cache size in GB.";
      };
    };

    storage = {
      url = lib.mkOption {
        type = lib.types.str;
        example = "s3://bucket/path";
        description = "Storage backend URL.";
      };
    };

    servers = {
      nfs = {
        enable = lib.mkEnableOption "NFS server for ZeroFS";
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0:2049" ];
          description = "Addresses to bind the NFS server to.";
        };
      };
      ninep = {
        enable = lib.mkEnableOption "9P server for ZeroFS";
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0:5564" ];
          description = "Addresses to bind the 9P server to.";
        };
        unixSocket = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "/tmp/zerofs.9p.sock";
          description = "Unix socket path for 9P (null to disable).";
        };
      };
      nbd = {
        enable = lib.mkEnableOption "NBD server for ZeroFS";
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "127.0.0.1:10809" ];
          description = "Addresses to bind the NBD server to.";
        };
        unixSocket = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "/tmp/zerofs.nbd.sock";
          description = "Unix socket path for NBD (null to disable).";
        };
      };
      rpc = {
        enable = lib.mkEnableOption "RPC server for ZeroFS";
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "127.0.0.1:7000" ];
          description = "Addresses to bind the RPC server to.";
        };
        unixSocket = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "/tmp/zerofs.rpc.sock";
          description = "Unix socket path for RPC (null to disable).";
        };
      };
      webui = {
        enable = lib.mkEnableOption "Web UI server for ZeroFS";
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0:8080" ];
          description = "Addresses to bind the Web UI to.";
        };
        uid = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "UID for Web UI access.";
        };
        gid = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "GID for Web UI access.";
        };
      };
    };

    aws = {
      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "http://192.168.1.50:3900";
        description = "S3-compatible endpoint URL (null for AWS).";
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east-1";
        description = "AWS region or S3 region.";
      };
      allowHttp = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow HTTP (non-HTTPS) connections.";
      };
      conditionalPut = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "redis://localhost:6380";
        description = "Redis URL for conditional put support (null to disable).";
      };
    };

    filesystem = {
      maxSizeGb = lib.mkOption {
        type = lib.types.nullOr lib.types.number;
        default = null;
        description = "Maximum filesystem size in GB (null for unlimited).";
      };
      compression = lib.mkOption {
        type = lib.types.str;
        default = "lz4";
        description = "Compression algorithm (e.g., 'lz4', 'zstd-3', 'zstd-11').";
      };
    };

    telemetry = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable anonymous telemetry.";
      };
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the encryption password.";
    };

    accessKeyIdFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the AWS access key ID.";
    };

    secretAccessKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the AWS secret access key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.passwordFile != null;
        message = "services.zerofs.passwordFile must be set when the service is enabled.";
      }
      {
        assertion = cfg.accessKeyIdFile != null;
        message = "services.zerofs.accessKeyIdFile must be set when the service is enabled.";
      }
      {
        assertion = cfg.secretAccessKeyFile != null;
        message = "services.zerofs.secretAccessKeyFile must be set when the service is enabled.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
    };
    users.groups.${cfg.group} = { };

    services.zerofs.package = lib.mkDefault zerofsPkg;

    services.redis.servers.zerofs = {
      user = cfg.user;
      enable = true;
      port = 6380;
    };

    # TODO: dragonflydb is currently unbuildable in nixos-26.05 due to
    # upstream source/submodule hash drift and abseil-cpp patch mismatch.
    # Re-enable once the nixpkgs package is fixed upstream.
    # nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "dragonflydb" ];
    #
    # services.dragonflydb = {
    #   enable = true;
    #   user = cfg.user;
    #   port = 6380;
    #   bind = "127.0.0.1";
    # };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cache.dir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    environment.systemPackages = [ zerofsPkg ];

    environment.etc."zerofs.toml".source = tomlFormat.generate "zerofs.toml" ({
      cache = {
        dir = cfg.cache.dir;
        disk_size_gb = cfg.cache.diskSizeGb;
        memory_size_gb = cfg.cache.memorySizeGb;
      };
      storage = {
        url = cfg.storage.url;
        encryption_password = "\${ZEROFS_PASSWORD}";
      };
      servers = lib.filterAttrs (_: v: v != { }) {
        nfs = lib.optionalAttrs cfg.servers.nfs.enable {
          addresses = cfg.servers.nfs.addresses;
        };
        ninep = lib.optionalAttrs cfg.servers.ninep.enable (
          {
            addresses = cfg.servers.ninep.addresses;
          }
          // lib.optionalAttrs (cfg.servers.ninep.unixSocket != null) {
            unix_socket = cfg.servers.ninep.unixSocket;
          }
        );
        nbd = lib.optionalAttrs cfg.servers.nbd.enable (
          {
            addresses = cfg.servers.nbd.addresses;
          }
          // lib.optionalAttrs (cfg.servers.nbd.unixSocket != null) {
            unix_socket = cfg.servers.nbd.unixSocket;
          }
        );
        rpc = lib.optionalAttrs cfg.servers.rpc.enable (
          {
            addresses = cfg.servers.rpc.addresses;
          }
          // lib.optionalAttrs (cfg.servers.rpc.unixSocket != null) {
            unix_socket = cfg.servers.rpc.unixSocket;
          }
        );
        webui = lib.optionalAttrs cfg.servers.webui.enable {
          addresses = cfg.servers.webui.addresses;
          uid = cfg.servers.webui.uid;
          gid = cfg.servers.webui.gid;
        };
      };
      aws = {
        secret_access_key = "\${AWS_SECRET_ACCESS_KEY}";
        access_key_id = "\${AWS_ACCESS_KEY_ID}";
        default_region = cfg.aws.region;
        allow_http = if cfg.aws.allowHttp then "true" else "false";
      }
      // lib.optionalAttrs (cfg.aws.endpoint != null) {
        endpoint = cfg.aws.endpoint;
      }
      // lib.optionalAttrs (cfg.aws.conditionalPut != null) {
        conditional_put = cfg.aws.conditionalPut;
      };
      filesystem = {
        compression = cfg.filesystem.compression;
      }
      // lib.optionalAttrs (cfg.filesystem.maxSizeGb != null) {
        max_size_gb = cfg.filesystem.maxSizeGb;
      };
      telemetry = {
        enabled = cfg.telemetry.enabled;
      };
    });

    systemd.services.zerofs = {
      description = "ZeroFS distributed filesystem";
      after = [
        "network.target"
        "redis-zerofs.service"
      ];
      wants = [ "redis-zerofs.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = 5;
        AmbientCapabilities = "cap_net_bind_service";
        ExecStart = pkgs.writeShellScript "zerofs-start" ''
          set -euo pipefail
          export ZEROFS_PASSWORD=$(cat ${cfg.passwordFile})
          export AWS_ACCESS_KEY_ID=$(cat ${cfg.accessKeyIdFile})
          export AWS_SECRET_ACCESS_KEY=$(cat ${cfg.secretAccessKeyFile})
          export HOME=${cfg.dataDir}
          exec ${zerofsPkg}/bin/zerofs run -c /etc/zerofs.toml
        '';
      };
    };
  };
}
