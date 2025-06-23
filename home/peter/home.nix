{ lib, pkgs, ... }:
let sources = ../dotfiles;
in {
  imports = [
    # Include the results of the hardware scan.
    # ./files/kubeconfig.nix
  ];

  # The home.stateVersion option does not have a default and must be set
  # Here goes the rest of your home-manager config, e.g. home.packages = [ pkgs.foo ];
  home = {
    stateVersion = "24.11";
    packages = with pkgs; [ zsh-powerlevel10k ];
  };

  # special programs setup
  programs.fzf.enable = true;
  programs.zoxide.enable = true;
  programs.direnv.enable = true;
  programs.kitty.shellIntegration.enableZshIntegration = true;
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    enableVteIntegration = true;
    historySubstringSearch.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "kubectl" "docker-compose" ];
    };
    plugins = [{
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }];
    initExtra = ''
      for file in ${sources}/*.zsh; do
              source "$file"
      done
      complete -C aws_completer aws
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
    };
    syntaxHighlighting.enable = true;
  };

  # git config
  programs.git = {
    lfs.enable = true;
    enable = true;
    userName = "peturparkur";
    userEmail = "peter@nagymathe.xyz";
    extraConfig = { core.editor = "nvim"; };
  };
}
