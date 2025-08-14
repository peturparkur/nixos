{ lib, pkgs, pkgs-stable, ... }: {
  nixpkgs.config.allowUnfree = true;
  imports = [
    # Include the results of the hardware scan.
    ./nvidia.nix
    # ./common/docker.nix
  ];

  environment.systemPackages = [ pkgs.docker-compose ];

  # https://nixos.org/manual/nixpkgs/unstable/index.html#cuda-using-docker-compose
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker = {
    enable = true;
    # enableNvidia = true; # We manually set this
    # extraPackages = [ pkgs.nvidia-docker ];
    daemon.settings = {
      features.cdi =
        true; # does not work on docker-compose but works on docker :(
      # error message: services.testing.deploy.resources.reservations.devices.0 capabilities is required
      experimental = true;
    };
    # TODO: nvidia runtime for docker -> figure out why it did not work
    # daemon.settings = {
    #   runtimes.nvidia = {
    #     path = "${pkgs-stable.nvidia-docker}/bin/nvidia-container-runtime";
    #   };
    # };
    # extraOptions = "--default-runtime=nvidia";
  };
}
