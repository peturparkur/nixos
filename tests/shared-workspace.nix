# Evaluation only: no rebuilds, allocations, mounts, or network connections.
# Run: nix eval --offline --impure --json --file tests/shared-workspace.nix
let
  flake = builtins.getFlake "path:${toString ../.}";
  lib = flake.inputs.nixpkgs.lib;
  hosts = flake.nixosConfigurations;
  server = hosts.amdmini-1.config;
  clients = map (host: hosts.${host}.config) [
    "amdmini-2"
    "elitedesk800"
    "peter-laptop"
  ];
  all = [ server ] ++ clients;
  mount = c: c.fileSystems."/mnt/shared";
  containsAll = expected: actual: lib.all (value: builtins.elem value actual) expected;
  script = server.systemd.services.shared-workspace-directory.script;
  checks = {
    validHosts = lib.all (c: lib.all (a: a.assertion) c.assertions) all;
    # Match the NixOS NFS wiki prerequisites, including integration supplied by
    # the pinned NixOS filesystem module rather than duplicated configuration.
    nfsClientPlumbing = lib.all (
      c:
      c.boot.supportedFilesystems.nfs
      && c.services.rpcbind.enable
      && lib.any (package: lib.getName package == "nfs-utils") c.system.fsPackages
    ) all;
    nfsServerPortDeclared = builtins.elem 2049 server.networking.firewall.allowedTCPPorts;
    serverOnly =
      server.services.nfs.server.enable && lib.all (c: !c.services.nfs.server.enable) clients;
    directoryBacking =
      (mount server).device == "/mnt/data/shared"
      && (mount server).fsType == "none"
      && (mount server).noCheck
      && !(mount server).autoFormat
      && !(mount server).autoResize
      && containsAll [
        "bind"
        "nosuid"
        "nodev"
        "nofail"
        "x-systemd.requires=shared-workspace-directory.service"
        "x-systemd.requires-mounts-for=/mnt/data"
      ] (mount server).options;
    noQuotaOrImageSetup =
      !(server.systemd.services ? shared-workspace-image)
      && !(builtins.elem "loop" (mount server).options)
      && !(builtins.elem "prjquota" server.fileSystems."/mnt/data".options)
      && !(lib.hasInfix "mkfs" script)
      && !(lib.hasInfix "fallocate" script);
    backingMountRequired =
      server.systemd.services.shared-workspace-directory.serviceConfig.RemainAfterExit
      && server.systemd.services.shared-workspace-directory.partOf == [ "mnt-shared.mount" ]
      && server.systemd.services.shared-workspace-directory.bindsTo == [ "mnt-data.mount" ]
      &&
        server.systemd.services.shared-workspace-directory.unitConfig.RequiresMountsFor == [ "/mnt/data" ]
      && lib.hasInfix "mountpoint -q /mnt/data" script
      && lib.hasInfix "test ! -L /mnt/data/shared" script;
    legacyDataGuard =
      lib.hasInfix "test -e /mnt/data/.shared-workspace/workspace.ext4" script
      && lib.hasInfix "test -L /mnt/data/.shared-workspace/workspace.ext4" script
      && lib.hasInfix "exit 1" script;
    exportPolicy =
      server.services.nfs.server.hostName == "192.168.1.45"
      && server.services.nfs.settings.nfsd.vers3 == false
      && server.services.nfs.settings.nfsd.vers4
      && server.services.nfs.settings.nfsd.udp == false
      && lib.hasInfix "/mnt/shared 192.168.1.0/24(rw,sync,fsid=0,no_subtree_check,root_squash,sec=sys,mountpoint)" server.services.nfs.server.exports;
    exportRequiresStorage =
      lib.all
        (
          name:
          let
            unit = server.systemd.services.${name};
          in
          containsAll [ "shared-workspace-ready.service" ] unit.requires
          && containsAll [ "shared-workspace-ready.service" ] unit.after
          && containsAll [ "mnt-shared.mount" "mnt-data.mount" ] unit.bindsTo
        )
        [
          "nfs-server"
          "nfs-mountd"
        ];
    directoryPermissions = lib.hasInfix "install -d -m 2770 -o 1000 -g 1000 /mnt/data/shared" script;
    exportIdentityChecked =
      server.systemd.services.shared-workspace-ready.requires == [ "mnt-shared.mount" ]
      && server.systemd.services.shared-workspace-ready.after == [ "mnt-shared.mount" ]
      && lib.hasInfix "mountpoint -q /mnt/data" server.systemd.services.shared-workspace-ready.script
      && lib.hasInfix "mountpoint -q /mnt/shared" server.systemd.services.shared-workspace-ready.script
      && lib.hasInfix "stat -c" server.systemd.services.shared-workspace-ready.script;
    offlineClients = lib.all (
      c:
      let
        fs = mount c;
      in
      fs.device == "192.168.1.45:/"
      && fs.fsType == "nfs"
      && !fs.neededForBoot
      && containsAll [
        "vers=4.2"
        "proto=tcp"
        "hard"
        "nosuid"
        "nodev"
        "_netdev"
        "nofail"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=60s"
        "x-systemd.mount-timeout=10s"
        "retry=0"
      ] fs.options
      && !(builtins.elem "soft" fs.options)
      && !(builtins.elem "softerr" fs.options)
    ) clients;
    consistentIdentity = lib.all (
      c:
      c.users.users.peter.uid == 1000
      && c.users.groups.peter.gid == 1000
      && c.services.nfs.idmapd.settings.General.Domain == "home.arpa"
    ) all;
    infrastructureIndependent = lib.all (
      c:
      lib.all
        (
          name:
          let
            unit = c.systemd.services.${name};
          in
          lib.all
            (
              key:
              let
                value = toString (unit.${key} or [ ]);
              in
              !(lib.hasInfix "mnt-shared" value) && !(lib.hasInfix "shared-workspace" value)
            )
            [
              "requires"
              "wants"
              "after"
              "bindsTo"
            ]
          && !(lib.hasInfix "/mnt/shared" (toString (unit.unitConfig.RequiresMountsFor or [ ])))
        )
        (
          lib.filter (name: c.services.${name}.enable) [
            "k3s"
            "garage"
          ]
        )
    ) all;
    objectMountsPreserved = lib.all (
      c:
      c.home-manager.users.peter.programs.rclone.remotes.garage.mounts."".mountPoint == "/mnt/garage"
      &&
        c.home-manager.users.peter.programs.rclone.remotes.backblaze.mounts.bbackblaze.mountPoint
        == "/mnt/backblaze"
    ) all;
  };
in
assert lib.assertMsg (lib.all (result: result) (
  lib.attrValues checks
)) "Shared workspace regression checks failed";
checks
