{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:
let
  server = "amdmini-1";
  isServer = config.networking.hostName == server;
  mountPoint = "/mnt/shared";
  sourceDirectory = "/mnt/data/shared";
  legacyImage = "/mnt/data/.shared-workspace/workspace.ext4";
  trustedNetwork = "192.168.1.0/24";
in
{
  config = lib.mkMerge [
    {
      boot.supportedFilesystems = [ "nfs" ];
      environment.systemPackages = [ pkgs.nfs-utils ];
      services.nfs.idmapd.settings.General.Domain = "home.arpa";
    }
    (lib.mkIf isServer {
      systemd.services.shared-workspace-directory = {
        description = "Prepare the shared-workspace directory on the data drive";
        # Revalidate storage on the next mount, and stop if the data mount stops.
        partOf = [ "mnt-shared.mount" ];
        bindsTo = [ "mnt-data.mount" ];
        after = [ "mnt-data.mount" ];
        unitConfig.RequiresMountsFor = [ "/mnt/data" ];
        path = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Do not create workspace files on the OS disk if the data mount is absent.
          mountpoint -q /mnt/data
          # An earlier image-backed deployment needs an explicit data migration,
          # not a silently empty replacement share. Never delete its data here.
          if test -e ${legacyImage} || test -L ${legacyImage}; then
            echo "Legacy workspace image exists at ${legacyImage}; migrate its data before switching to ${sourceDirectory}." >&2
            exit 1
          fi
          test ! -L ${sourceDirectory}
          # Only change the directory itself, never recursively chown its contents.
          install -d -m 2770 -o ${toString config.users.users.peter.uid} -g ${toString config.users.groups.peter.gid} ${sourceDirectory}
        '';
      };

      fileSystems.${mountPoint} = {
        device = sourceDirectory;
        fsType = "none";
        noCheck = true;
        options = [
          "bind"
          "nosuid"
          "nodev"
          "nofail"
          "x-systemd.requires=shared-workspace-directory.service"
          "x-systemd.requires-mounts-for=/mnt/data"
        ];
      };

      systemd.services.shared-workspace-ready = {
        description = "Verify shared-workspace backing storage before exporting";
        requires = [ "mnt-shared.mount" ];
        after = [ "mnt-shared.mount" ];
        bindsTo = [
          "mnt-shared.mount"
          "mnt-data.mount"
        ];
        path = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mountpoint -q /mnt/data
          mountpoint -q ${mountPoint}
          # The export must be the intended directory, not a leftover image mount.
          test "$(stat -c '%d:%i' ${sourceDirectory})" = "$(stat -c '%d:%i' ${mountPoint})"
        '';
      };

      services.nfs = {
        server = {
          enable = true;
          hostName = networkTopology.${server};
          exports = {
            ${mountPoint}.${trustedNetwork} = [
              "rw"
              "sync"
              "fsid=0"
              "no_subtree_check"
              "root_squash"
              "sec=sys"
              # Refuse to export the underlying directory if the bind mount is absent.
              "mountpoint"
            ];
          };
        };
        settings.nfsd = {
          vers3 = false;
          vers4 = true;
          udp = false;
          tcp = true;
        };
      };

      # Both daemons must wait for real backing storage and its permissions.
      systemd.services.nfs-server = {
        requires = [ "shared-workspace-ready.service" ];
        after = [ "shared-workspace-ready.service" ];
        bindsTo = [
          "mnt-shared.mount"
          "mnt-data.mount"
        ];
      };
      systemd.services.nfs-mountd = {
        requires = [ "shared-workspace-ready.service" ];
        after = [ "shared-workspace-ready.service" ];
        bindsTo = [
          "mnt-shared.mount"
          "mnt-data.mount"
        ];
      };
      networking.firewall.allowedTCPPorts = [ 2049 ];
    })
    (lib.mkIf (!isServer) {
      fileSystems.${mountPoint} = {
        device = "${networkTopology.${server}}:/";
        fsType = "nfs";
        options = [
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
        ];
      };
    })
  ];
}
