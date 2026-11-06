# Evaluation-only regression checks; no secrets are decrypted and nothing is mounted.
# Run: nix eval --offline --impure --json --file tests/rclone-mounts.nix
let
  flake = builtins.getFlake (toString ../.);
  lib = flake.inputs.nixpkgs.lib;
  hosts = flake.nixosConfigurations;
  mkMount = import ../home/lib/rclone-mount.nix { gid = 1000; };
  defaultMount = mkMount {
    cacheName = "test";
    mountPoint = "/mnt/test";
  };
  customMount = mkMount {
    cacheName = "test";
    mountPoint = "/mnt/test";
    vfsCacheMaxSize = "25G";
  };
  noFailedAssertions = c: lib.all (a: a.assertion) c.assertions;
  hasArg = arg: unit: lib.any (command: lib.hasInfix arg command) unit.Service.ExecStart;
  lifecyclePolicy =
    mountPoint: unit:
    unit.Service.Type == "notify"
    && unit.Service.TimeoutStartSec == "90s"
    && unit.Service.TimeoutStartFailureMode == "kill"
    && unit.Service.TimeoutStopSec == "10s"
    && unit.Service.TimeoutStopFailureMode == "kill"
    && unit.Service.KillMode == "control-group"
    && unit.Service.SendSIGKILL
    && unit.Service.FinalKillSignal == "SIGKILL"
    && unit.Service.ExecStop == "-/run/wrappers/bin/fusermount3 -uz ${lib.escapeShellArg mountPoint}"
    && unit.Service.ExecStopPost == unit.Service.ExecStop
    && unit.Unit.DefaultDependencies == false
    && unit.Unit.Before == [ "shutdown.target" ]
    && unit.Unit.Conflicts == [ "shutdown.target" ]
    && unit.Unit.Requires == [ "rclone-config.service" ]
    &&
      lib.sort builtins.lessThan unit.Unit.After == [
        "basic.target"
        "rclone-config.service"
      ];
  baseline =
    c:
    let
      home = c.home-manager.users.peter;
      unit = home.systemd.user.services."rclone-mount:@garage";
      mount = home.programs.rclone.remotes.garage.mounts."";
      directory = c.systemd.tmpfiles.settings."10-rclone-mounts"."/mnt/garage".d;
    in
    noFailedAssertions c
    && c.users.users.peter.linger
    && c.programs.fuse.userAllowOther
    && directory.type == "d"
    && directory.age == "-"
    && directory.user == "peter"
    && directory.group == c.users.users.peter.group
    && mount.options.gid == c.users.groups.peter.gid
    && mount.options.file-perms == "0660"
    && mount.options.dir-perms == "0770"
    && mount.options.cache-dir == "%C/rclone/garage"
    && home.programs.rclone.requiresUnit == null
    &&
      home.programs.rclone.remotes.garage.secrets.access_key_id
      == c.sops.secrets."rclone/garage/access-key-id".path
    && unit.Service.Type == "notify"
    && unit.Service.Restart == "on-failure"
    && unit.Service.RestartSec == "15s"
    && unit.Unit.StartLimitIntervalSec == 0
    && unit.Install.WantedBy == [ "default.target" ]
    && unit.Unit.Requires == [ "rclone-config.service" ]
    && hasArg "garage: /mnt/garage" unit
    && hasArg "--default-permissions" unit
    && hasArg "--allow-other" unit
    && lib.hasInfix "/mnt/garage" unit.Service.ExecStopPost;
  configuredRemotes =
    c:
    let
      home = c.home-manager.users.peter;
      remotes = home.programs.rclone.remotes;
      expected = [
        {
          name = "garage";
          path = "";
          mountPoint = "/mnt/garage";
          secret = "garage";
          cacheSize = "10G";
        }
        {
          name = "garagek3s";
          path = "";
          mountPoint = "/mnt/garage-k3s";
          secret = "garage-k3s";
          cacheSize = "10G";
        }
        {
          name = "backblaze";
          path = "bbackblaze";
          mountPoint = "/mnt/backblaze";
          secret = "backblaze";
          cacheSize = "5G";
        }
      ];
    in
    lib.all (
      spec:
      let
        remote = remotes.${spec.name};
        mount = remote.mounts.${spec.path};
        unit = home.systemd.user.services."rclone-mount:${spec.path}@${spec.name}";
      in
      (
        if spec.name == "backblaze" then
          remote.config == {
            type = "b2";
          }
          && remote.secrets.account == c.sops.secrets."rclone/backblaze/access-key-id".path
          && remote.secrets.key == c.sops.secrets."rclone/backblaze/secret-access-key".path
        else
          remote.config.type == "s3"
          && remote.config.provider == "Other"
          && remote.config.force_path_style
          && remote.secrets.access_key_id == c.sops.secrets."rclone/${spec.secret}/access-key-id".path
          && remote.secrets.secret_access_key == c.sops.secrets."rclone/${spec.secret}/secret-access-key".path
      )
      && mount.mountPoint == spec.mountPoint
      && mount.options.cache-dir == "%C/rclone/${spec.name}"
      && mount.options.vfs-cache-max-size == spec.cacheSize
      && hasArg "--vfs-cache-max-size=${spec.cacheSize}" unit
      && mount.options.gid == c.users.groups.peter.gid
      && mount.options.default-permissions
      && mount.options.file-perms == "0660"
      && mount.options.dir-perms == "0770"
      && unit.Service.RestartSec == "15s"
      && lifecyclePolicy spec.mountPoint unit
      && hasArg "${spec.name}:${spec.path} ${spec.mountPoint}" unit
      && builtins.hasAttr spec.mountPoint c.systemd.tmpfiles.settings."10-rclone-mounts"
    ) expected
    && remotes.garagek3s.config.endpoint == "http://192.168.1.169:3900";
  base = hosts.amdmini-1;
  extra =
    (base.extendModules {
      modules = [
        {
          home-manager.users.peter.programs.rclone.remotes = {
            otherGarage = {
              config = {
                type = "s3";
                provider = "Other";
              };
              secrets = {
                access_key_id = "/run/example/other-access-key-id";
                secret_access_key = "/run/example/other-secret-access-key";
              };
              mounts."bucket/prefix" = mkMount {
                cacheName = "garage-other";
                mountPoint = "/mnt/garage-other";
                vfsCacheMaxSize = "25G";
              };
            };
            testB2 = {
              config.type = "b2";
              secrets = {
                account = "/run/example/b2-id";
                key = "/run/example/b2-key";
              };
              mounts.archive = {
                enable = true;
                mountPoint = "/mnt/b2";
                options.cache-dir = "%C/rclone/b2";
              };
              mounts.disabled = {
                enable = false;
                mountPoint = "/mnt/disabled";
              };
            };
          };
        }
      ];
    }).config;
  extraHome = extra.home-manager.users.peter;
  otherUser =
    (base.extendModules {
      modules = [
        {
          users.groups.mount-test = { };
          users.users.mount-test = {
            isNormalUser = true;
            group = "mount-test";
          };
          home-manager.users.mount-test = {
            home.stateVersion = "26.05";
            programs.rclone = {
              enable = true;
              remotes.fixture = {
                config.type = "local";
                mounts."/tmp" = {
                  enable = true;
                  mountPoint = "/mnt/mount-test";
                };
              };
            };
          };
        }
      ];
    }).config;
  collision =
    (base.extendModules {
      modules = [
        {
          home-manager.users.peter.programs.rclone.remotes.garage.mounts.duplicate = {
            enable = true;
            mountPoint = "/mnt/garage";
          };
        }
      ];
    }).config;
  filesystemCollision =
    (base.extendModules {
      modules = [
        {
          home-manager.users.peter.programs.rclone.remotes.garage.mounts.filesystem = {
            enable = true;
            mountPoint = "/boot";
          };
        }
      ];
    }).config;
  checks = {
    cacheSizeDefault = defaultMount.options.vfs-cache-max-size == "10G";
    cacheSizeOverride =
      customMount.options.vfs-cache-max-size == "25G"
      && (customMount.options // { vfs-cache-max-size = "10G"; }) == defaultMount.options
      &&
        hasArg "--vfs-cache-max-size=25G"
          extraHome.systemd.user.services."rclone-mount:bucket.prefix@otherGarage";
    allHosts = lib.all (host: baseline hosts.${host}.config && configuredRemotes hosts.${host}.config) (
      lib.attrNames hosts
    );
    systemCredentials = lib.all (
      host:
      let
        c = hosts.${host}.config;
        home = c.home-manager.users.peter;
        names = [
          "rclone/garage/access-key-id"
          "rclone/garage/secret-access-key"
          "rclone/garage-k3s/access-key-id"
          "rclone/garage-k3s/secret-access-key"
          "rclone/backblaze/access-key-id"
          "rclone/backblaze/secret-access-key"
        ];
      in
      lib.all (
        name:
        let
          secret = c.sops.secrets.${name};
        in
        secret.owner == "peter"
        && secret.group == c.users.users.peter.group
        && secret.mode == "0400"
        && secret.sopsFile == c.sops.defaultSopsFile
        && secret.path == "/run/secrets/${name}"
      ) names
      && home.sops.secrets == { }
      && !(home.systemd.user.services ? sops-nix)
      && !(home.home.activation ? sops-nix)
      && !(home.systemd.user.services.rclone-config.Unit ? Requires)
    ) (lib.attrNames hosts);
    infrastructureIndependent = lib.all (
      host:
      let
        c = hosts.${host}.config;
        mountPoints = lib.concatMap (
          remote:
          map (mount: mount.mountPoint) (lib.filter (mount: mount.enable) (lib.attrValues remote.mounts))
        ) (lib.attrValues c.home-manager.users.peter.programs.rclone.remotes);
        services = lib.filter (name: c.services.${name}.enable) [
          "k3s"
          "garage"
        ];
      in
      lib.all (
        name:
        let
          service = c.systemd.services.${name};
          dependencies = lib.concatMapStringsSep " " (key: toString (service.unitConfig.${key} or "")) [
            "Requires"
            "Wants"
            "After"
            "Before"
            "BindsTo"
            "PartOf"
            "RequiresMountsFor"
          ];
        in
        !(lib.hasInfix "rclone-" dependencies)
        && !(lib.hasInfix "mnt-garage" dependencies)
        && !(lib.hasInfix "mnt-backblaze" dependencies)
        && lib.all (path: !(lib.hasInfix path dependencies)) mountPoints
      ) services
      && (
        if c.services.garage.enable then
          lib.all
            (
              path: lib.all (mountPoint: path != mountPoint && !(lib.hasPrefix "${mountPoint}/" path)) mountPoints
            )
            (
              [ c.services.garage.settings.metadata_dir ]
              ++ map (directory: directory.path) c.services.garage.settings.data_dir
            )
        else
          true
      )
    ) (lib.attrNames hosts);
    zerofsRemoved = lib.all (
      host:
      let
        c = hosts.${host}.config;
      in
      !(builtins.hasAttr "zerofs" hosts.${host}.options.services)
      && !(builtins.hasAttr "/mnt/zerofs" c.fileSystems)
      && !(builtins.hasAttr "/mnt/backblaze" c.fileSystems)
      && !(builtins.elem "zerofs" c.users.users.peter.extraGroups)
      && lib.all (package: lib.getName package != "zerofs") c.environment.systemPackages
      && lib.all (name: !(lib.hasPrefix "zerofs-" name)) (lib.attrNames c.systemd.services)
    ) (lib.attrNames hosts);
    multipleProviders =
      noFailedAssertions extra
      && extraHome.programs.rclone.remotes.testB2.config.type == "b2"
      &&
        extraHome.programs.rclone.remotes.otherGarage.secrets.access_key_id
        != extraHome.programs.rclone.remotes.garage.secrets.access_key_id
      &&
        hasArg "otherGarage:bucket/prefix /mnt/garage-other"
          extraHome.systemd.user.services."rclone-mount:bucket.prefix@otherGarage"
      && extraHome.systemd.user.services."rclone-mount:archive@testB2".Service.RestartSec == "15s"
      && lifecyclePolicy "/mnt/b2" extraHome.systemd.user.services."rclone-mount:archive@testB2"
      && builtins.hasAttr "/mnt/b2" extra.systemd.tmpfiles.settings."10-rclone-mounts";
    disabledMountIgnored =
      !(builtins.hasAttr "/mnt/disabled" extra.systemd.tmpfiles.settings."10-rclone-mounts")
      && !(builtins.hasAttr "rclone-mount:disabled@testB2" extraHome.systemd.user.services);
    separateUserIntegration =
      noFailedAssertions otherUser
      && otherUser.users.users.mount-test.linger
      &&
        lifecyclePolicy "/mnt/mount-test"
          otherUser.home-manager.users.mount-test.systemd.user.services."rclone-mount:.tmp@fixture"
      && otherUser.systemd.tmpfiles.settings."10-rclone-mounts"."/mnt/mount-test".d.user == "mount-test"
      && otherUser.systemd.tmpfiles.settings."10-rclone-mounts"."/mnt/mount-test".d.group == "mount-test"
      &&
        otherUser.home-manager.users.mount-test.systemd.user.services."rclone-mount:.tmp@fixture".Service.RestartSec
        == "15s";
    duplicateMountRejected = !(noFailedAssertions collision);
    filesystemMountCollisionRejected = !(noFailedAssertions filesystemCollision);
  };
in
assert lib.assertMsg (lib.all (result: result) (
  lib.attrValues checks
)) "rclone mount regression checks failed";
checks
