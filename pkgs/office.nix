{ pkgs, ... }: {
  environment.systemPackages = with pkgs;
    [
      libreoffice-fresh # for general office tools
    ];
}
