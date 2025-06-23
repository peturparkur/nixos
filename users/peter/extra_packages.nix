{ pkgs, ... }: {
  users.users.peter.packages = with pkgs; [
    firefox
    poetry
    kitty
    # vscode
    alejandra
    nil
    brave
    woeusb # for windows bootable usb creation
    element-desktop # communication
    obsidian # note taking
    tor-browser
    # megasync
    mullvad-vpn
    discord
    vesktop # discord screensharing with audio
    # thunderbird
    kubebuilder # for creating kubernetes operators
    teams-for-linux # unofficial microsoft teams
  ];
}
