{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.jujutsu # git compatible vcs - https://github.com/martinvonz/jj
  ];
}
