{ lib, pkgs, ... }: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall =
      true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall =
      true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall =
      true; # Open ports in the firewall for Steam Local Network Game Transfers
  };
  # This doesn't actually work...
  # At least I could not figure out how...
  # TODO: Figure out how this works
  programs.steam.gamescopeSession.enable =
    true; # this solves fullscreen problems for some games; eg.: Bethesda

  # additional game launcher
  environment.systemPackages = with pkgs; [
    steamcmd
    heroic
    lutris
    # openssl_1_1
    r2modman
    # protonup default installation directory is .steam/root/compatibilitytools.d
    protonup-ng
    protonup-qt
    winetricks
    wine64 # gaming
    umu-launcher
  ];
}
