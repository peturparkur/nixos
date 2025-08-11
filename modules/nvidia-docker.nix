{ lib, pkgs, pkgs-stable, ... }: {
  nixpkgs.config.allowUnfree = true;
  imports = [
    # Include the results of the hardware scan.
    ./nvidia.nix
    # ./common/docker.nix
  ];

  environment.systemPackages = [ pkgs.docker-compose ];

  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker = lib.mkDefault {
    enable = true;
    # enableNvidia = true; # We manually set this
    extraPackages = [ pkgs.nvidia-docker ];
    # TODO: nvidia runtime for docker -> figure out why it did not work
    # daemon.settings = {
    #   runtimes.nvidia = {
    #     path = "${pkgs-stable.nvidia-docker}/bin/nvidia-container-runtime";
    #   };
    # };
    # extraOptions = "--default-runtime=nvidia";
  };
}
