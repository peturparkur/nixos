{ ... }: {
  services = {
    syncthing = {
      enable = true;
      user = "peter";
      dataDir =
        "/home/peter/shared/syncthing"; # Default folder for new synced folders
      configDir =
        "/home/peter/.config/syncthing"; # Folder for Syncthing's settings and keys
    };
  };
}
