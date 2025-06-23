{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    xwayland
    kdePackages.xwaylandvideobridge # wayland screenshare
  ];
}
