{ config, pkgs, ... }: {

  environment.systemPackages = with pkgs; [ docker-compose ];
  virtualisation.docker = {
    enable = true;
    # start dockerd on boot.
    # This is required for containers which are created with the `--restart=always` flag to work.
    enableOnBoot = true;

    # to allow ipv6 in docker
    daemon.settings = {
      ipv6 = true;
      fixed-cidr-v6 = "fd00::/80";
    };
  };
}
