{ lib, pkgs, ... }:
let
  sources = ../dotfiles;
in
{
  imports = [
    # Include the results of the hardware scan.
    # ./files/kubeconfig.nix
  ];

  # The home.stateVersion option does not have a default and must be set
  # Here goes the rest of your home-manager config, e.g. home.packages = [ pkgs.foo ];
  home = {
    stateVersion = "24.11";
    packages = with pkgs; [ zsh-powerlevel10k ];

    # User-local tooling directory. Binaries dropped into ~/.local/bin are
    # picked up on PATH but are NOT managed by NixOS: they may be replaced or
    # deleted freely, independent of system rebuilds.
    sessionPath = [ "$HOME/.local/bin" ];
  };

  # special programs setup
  programs.fzf.enable = true;
  programs.zoxide.enable = true;
  programs.direnv.enable = true;
  # Kitty is installed as a system package; this block only generates
  # ~/.config/kitty/kitty.conf with the shortcuts below.
  #
  # Modifier policy for this setup:
  #   Ctrl+H / Ctrl+L   Neovim split navigation
  #   Ctrl+Shift+...    Kitty defaults (new tab, close tab, layouts, ...)
  #   Super+...         Hyprland (compositor) shortcuts
  #
  # Tab navigation mirrors Neovim's window navigation.  Note that mapping
  # Ctrl+H/Ctrl+L in kitty means the running program (zsh, fzf, ...) no longer
  # receives them, so readline backspace-word (Ctrl+H) is shadowed here.
  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    keybindings = {
      # Neovim-style tab movement: left = previous, right = next.
      "ctrl+h" = "prev_tab";
      "ctrl+l" = "next_tab";

      # Direct tab selection, 1-based and matching the tab bar labels.
      "ctrl+alt+1" = "goto_tab 1";
      "ctrl+alt+2" = "goto_tab 2";
      "ctrl+alt+3" = "goto_tab 3";
      "ctrl+alt+4" = "goto_tab 4";
      "ctrl+alt+5" = "goto_tab 5";
      "ctrl+alt+6" = "goto_tab 6";
      "ctrl+alt+7" = "goto_tab 7";
      "ctrl+alt+8" = "goto_tab 8";
      "ctrl+alt+9" = "goto_tab 9";
    };
  };
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    enableVteIntegration = true;
    historySubstringSearch.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "kubectl"
        "docker-compose"
      ];
    };
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
    initContent = ''
      for file in ${sources}/*.zsh; do
              source "$file"
      done
    '';
    shellAliases = {
      ll = "ls -l";
      k = "kubectl";
      kns = "kubens";
      ktx = "kubectx";
      g = "git";
      cd = "z";
      cdi = "zi";
      j = "just";
      icat = "kitten icat";
      ssh = "kitten ssh";
    };
    syntaxHighlighting.enable = true;
  };

  # git config
  programs.git = {
    lfs.enable = true;
    enable = true;
    settings.user = {
      name = "peturparkur";
      email = "peter@nagymathe.xyz";
    };
    settings.core.editor = "nvim";
    settings.credential.helper = "store";
  };
}
