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
        type = lib.types.enum [
          "nfs"
          "9p"
        ];
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

      automount = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Use systemd automount for this mount.
          Recommended for network filesystems because it defers
          mounting until the path is first accessed, retries on
          transient failures, and avoids blocking boot if the
          server is unreachable.
        '';
      };

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          User name that owns the mount point. For 9P mounts this
          also automatically adds `uid=` and `gid=` mount options so
          the filesystem is accessible by that user.
        '';
      };

      group = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Group name for the mount point. Defaults to `user` when
          that option is set.
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

  getDevice =
    mount:
    if mount.device != null then
      mount.device
    else if mount.protocol == "nfs" then
      "${mount.server}:/"
    else
      mount.server;

  getDefaultOptions =
    mount:
    (if mount.protocol == "nfs" then
      [
        "_netdev"
        "port=${toString (getPort mount)}"
      ]
    else
      [
        "_netdev"
        "trans=tcp"
        "port=${toString (getPort mount)}"
      ])
    ++ [ "nofail" "x-systemd.mount-timeout=30s" ];

  getAutomountOptions =
    mount:
    if mount.automount then
      [
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=300"
      ]
    else
      [ ];

  getAllOptions = mount: (getDefaultOptions mount) ++ mount.options ++ (getAutomountOptions mount);

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

    # Ensure all mount point directories exist and have correct ownership.
    # Using 'D' instead of 'd' so permissions are fixed on every boot.
    systemd.tmpfiles.rules = lib.mapAttrsToList (
      _name: mount:
      let
        user = if mount.user != null then mount.user else "root";
        group = if mount.group != null then mount.group else if mount.user != null then mount.user else "users";
      in
      "D '${mount.mountPoint}' 0775 ${user} ${group} -"
    ) cfg.mounts;

    # Register each mount in NixOS fileSystems.
    fileSystems = lib.mapAttrs' (
      _name: mount:
      let
        userOpts = lib.optionals (mount.user != null && mount.protocol == "9p") (
          let
            uid = toString (config.users.users.${mount.user}.uid or 1000);
            gid = toString (config.users.groups.${if mount.group != null then mount.group else mount.user}.gid or 1000);
          in
          [
            "uid=${uid}"
            "gid=${gid}"
            "dfltuid=${uid}"
            "dfltgid=${gid}"
          ]
        );
      in
      lib.nameValuePair mount.mountPoint {
        device = getDevice mount;
        fsType = mount.protocol;
        options = (getDefaultOptions mount) ++ userOpts ++ mount.options ++ (getAutomountOptions mount);
      }
    ) cfg.mounts;
  };
}
