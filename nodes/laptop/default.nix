{ pkgs, ... }: {
  networking = {
    hostName = "peter-laptop"; # Define your hostname.
    networkmanager.enable = true;
    dhcpcd.enable = true;

    # to have access to tailscale magicdns resolver
    search = [ "tigris-bee.ts.net" ];
    networkmanager.insertNameservers = [
      "100.100.100.100" # tailscale
      "192.168.0.167" # localdns - technitium-tcp
      "192.168.0.168" # localdns - technitium-udp
      "1.1.1.1"
      "8.8.8.8"
      "8.8.4.4"
    ];
    # nameservers = [
    #   "1.1.1.1"
    #   "8.8.8.8"
    #   # "8.8.4.4"
    #   "100.100.100.100"
    # ];
    extraHosts = ''
      192.168.0.162 traefik.nagymathe.xyz
    '';
  };

  imports = [
    ./hardware.nix
    # ../../users/peter/peter.nix # user is imported in nix
    ../../modules/locale_gb.nix
    ../../modules/timezones/paris.nix
    ../../modules/gnome_desktop.nix
    ../../modules/nix_ld.nix
    ../../modules/docker.nix
    ../../modules/nvidia.nix
    ../../modules/nvidia-docker.nix
    ../../modules/hyprland.nix
    ../../modules/programming_languages.nix
    ../../modules/weird/skip_network_manager.nix
    ../../services/syncthing.nix
    ../../services/mullvad.nix
    ../../pkgs/tailscale.nix
    ../../pkgs/jujutsu.nix
    ../../pkgs/gaming.nix
    ../../pkgs/fonts.nix
    ../../pkgs/screen_share.nix
    ../../pkgs/video_viewer.nix
    ../../pkgs/office.nix
    ../../pkgs/fonts.nix
  ];

  # system.stateVersion = "unstable";
  # system.stateVersion = "24.11";

  # Bootloader.
  # boot.loader.systemd-boot.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure console keymap
  console.keyMap = "uk";

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # stored in users.nix
  # environment.sessionVariables = { LD_LIBRARY_PATH = "$NIX_LD_LIBRARY_PATH"; }; # this makes numpy work but breaks firefox
  # environment.sessionVariables = {
  #   NVIM_PROFILE = "HOME";
  #   KUBE_EDITOR = "nvim";
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    fd # better find
    direnv
    wget
    curl
    lshw
    git
    neovim
    jq # json query - cli processor

    # k3s management
    kubernetes-helm

    firefox
    tor-browser
    mullvad-browser

    # archives
    zip
    unzip
    p7zip
    zstd
    zstd

    # networking
    mtr
    iperf3 # measure TCP and UDP bandwidth performance
    nmap # network discoverability and security audit
    ldns # replacement for dig. Command is drill

    # tailscale
    # tailscale-systray
    ripgrep
    just
    libgcc # for general c compilation
    gccgo13 # gcc-13
    vscode # temporary
    unrar
    # languages
    # obsidian # this should be user level
    omnisharp-roslyn

    awscli2 # aws cli for s3 usage
  ];
}
