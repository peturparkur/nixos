{ config, pkgs, ... }: {

  environment.systemPackages = with pkgs; [ docker-compose docker-buildx ];

  # Symlink docker-buildx into the CLI plugins directory so Docker Compose
  # can find it when using the Bake backend. Even though `docker buildx`
  # works via PATH, Compose v2 looks in the plugin directory specifically.
  # system.activationScripts.docker-buildx = ''
  #   mkdir -p /usr/lib/docker/cli-plugins
  #   ln -sf ${pkgs.docker-buildx}/bin/docker-buildx /usr/lib/docker/cli-plugins/docker-buildx
  # '';

  virtualisation.docker = {
    enable = true;
    # start dockerd on boot.
    # This is required for containers which are created with the `--restart=always` flag to work.
    enableOnBoot = true;

    # to allow ipv6 in docker
    daemon.settings = {
      ipv6 = true;
      dns = [ "1.1.1.1" "8.8.8.8" ];
      fixed-cidr-v6 = "fd00::/80";
    };
  };
}
