{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    mpv # video viewer
    vlc # video viewer
  ];
}
