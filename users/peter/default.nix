{ pkgs, ... }: {
  programs.zsh.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  environment.sessionVariables = {
    NVIM_PROFILE = "HOME";
    KUBE_EDITOR = "nvim";
  };
  programs = { neovim = { defaultEditor = true; }; };

  users = {
    defaultUserShell = pkgs.zsh;
    groups = { peter = { }; };
    users = {
      root = {
        initialHashedPassword =
          "$y$j9T$PejWEf9rSNRTZHBUW1OfU1$/kude0HY0CKxFZPdrlcuUupfSKgX1p85oNfxb3Y7C08";
      };
      peter = {
        name = "peter";
        description = "Peter";
        isNormalUser = true;
        group = "peter";
        home = "/home/peter";
        createHome = true;
        useDefaultShell = true;
        # hashed password can be generated with mkpasswd
        initialHashedPassword =
          "$y$j9T$PejWEf9rSNRTZHBUW1OfU1$/kude0HY0CKxFZPdrlcuUupfSKgX1p85oNfxb3Y7C08";
        # wheel to allow sudo
        extraGroups = [ "wheel" "audio" "networkmanager" "docker" ];
        # packages = with pkgs; [ ];

        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChxNfW40HxyvipBb5A8yU5iwBglrTD53yQRVwup6/lx peter@nixos"
        ];
      };
    };
  };
}

