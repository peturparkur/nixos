{ ... }: {
  # Hackety hack to allow rebuild
  systemd.services.NetworkManager-wait-online.enable = false;
}
