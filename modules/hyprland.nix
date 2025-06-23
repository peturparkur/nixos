{ lib, pkgs, ... }:
let
in {
  programs.hyprland = {
    enable = true;
    xwayland.enable = true; # jetbrains needs it, spotify and so on
    # enableNvidiaPatches = true; # no longer required
  };

  environment.sessionVariables = {
    # invisible cursor
    WSL_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1";
  };

  # set of things I need managing
  # -
  #
  #
  #
  #
  #
  #

  environment.systemPackages = with pkgs; [
    waybar
    dunst
    libnotify
    rofi-wayland
  ];
}
