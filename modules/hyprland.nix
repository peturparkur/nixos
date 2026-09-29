{ lib, pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true; # Keep compatibility with X11 applications.
  };

  # These variables make the common Chromium/Electron and Firefox applications
  # behave as native Wayland clients.  The Hyprland configuration itself is
  # kept in Home Manager so it belongs to Peter's laptop session only.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  # Small, deliberately boring building blocks used by the user configuration.
  # The compositor, Waybar and notification settings are configured in
  # home/peter/programs/hyprland.nix.
  environment.systemPackages = with pkgs; [
    brightnessctl # set laptop/display backlight from the shell or keybinds
    blueman # Bluetooth manager (pairing, devices) for the tray
    gnome-control-center # GTK settings app: power, sound, network, users
    libnotify # send_desktop_notification CLI, used for script notifications
    networkmanagerapplet # NetworkManager system-tray applet
    nwg-displays # graphical monitor/refresh-rate/scale editor for Hyprland
    udiskie # auto-mounts USB drives and shows them in the tray
    pavucontrol # PulseAudio/PipeWire mixer for input and output selection
    playerctl # MPRIS media control (play/pause/next) for media keys
    slurp # selects a screen region, used together with grim
    swaybg # plain wallpaper/background renderer
    wl-clipboard # wl-copy / wl-paste Wayland clipboard access
    wofi # application launcher and dmenu-style prompt used by keybinds
  ];

  # Hyprlock uses the normal NixOS PAM stack when the screen is locked.
  # These are desktop-independent services, but making them explicit keeps
  # USB storage and graphical file access working in a Hyprland-only session.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  security.pam.services.hyprlock = { };
}
