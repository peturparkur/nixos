{ config, pkgs, ... }: {
  # List packages installed in system profile. To search, run:
  environment.systemPackages = with pkgs; [ tailscale tailscale-systray ];

  sops.secrets."tailscale_authkey" = { }; # initialize secret key
  # Tailscale and its systemd authentication service
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale_authkey".path;
  };
}
