{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.virtualFs;

  mountSubmodule = lib.types.submodule {
    options = {
      protocol = lib.mkOption {
        type = lib.types.enum [ "nfs" "9p" ];
        description = "Network filesystem protocol to use.";
      };

      server = lib.mkOption {
        type = lib.types.str;
        example = "192.168.1.50";
        description = "Server hostname or IP address.";
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Server port. If not specified, defaults to 2049 for NFS
          and 5564 for 9P.
        '';
      };

      mountPoint = lib.mkOption {
        type = lib.types.path;
        description = "Local mount point.";
      };

      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Override the mount device string.
          Defaults to "<server>:/" for NFS and "<server>" for 9P.
        '';
      };

      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional mount options passed to mount(8).
          For 9P, sensible defaults (_netdev, trans=tcp, port)
          are added automatically. For NFS, _netdev and port
          are added automatically.
        '';
      };
    };
  };

  getPort =
    mount:
    if mount.port != null then
      mount.port
    else if mount.protocol == "nfs" then
      2049
    else
      5564;

  getDevice = mount:
    if mount.device != null then
      mount.device
    else if mount.protocol == "nfs" then
      "${mount.server}:/"
    else
      mount.server;

  getDefaultOptions = mount:
    if mount.protocol == "nfs" then
      [ "_netdev" "port=${toString (getPort mount)}" ]
    else
      [ "_netdev" "trans=tcp" "port=${toString (getPort mount)}" ];

  getAllOptions = mount: (getDefaultOptions mount) ++ mount.options;

  has9pMount = lib.any (m: m.protocol == "9p") (lib.attrValues cfg.mounts);
in

{
  options.services.virtualFs = {
    enable = lib.mkEnableOption "virtual filesystem mounts";

    mounts = lib.mkOption {
      type = lib.types.attrsOf mountSubmodule;
      default = { };
      description = "Attribute set of named virtual filesystem mounts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure 9p kernel modules are available when any mount uses 9P.
    boot.kernelModules = lib.mkIf has9pMount [
      "9p"
      "9pnet"
      "9pnet_tcp"
    ];

    # Ensure all mount point directories exist.
    systemd.tmpfiles.rules = lib.mapAttrsToList (
      _name: mount: "d '${mount.mountPoint}' 0755 root root -"
    ) cfg.mounts;

    # Register each mount in NixOS fileSystems.
    fileSystems = lib.mapAttrs' (
      _name: mount:
      lib.nameValuePair mount.mountPoint {
        device = getDevice mount;
        fsType = mount.protocol;
        options = getAllOptions mount;
      }
    ) cfg.mounts;
  };
}
