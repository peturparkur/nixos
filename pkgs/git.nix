{ ... }: {
  programs = {
    # Version control application.
    git = {
      enable = true;
      lfs.enable = true;
    };
  };
}
