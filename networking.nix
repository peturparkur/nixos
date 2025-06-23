{ ... }: {
  imports = [ ./services/openssh.nix ];
  networking = {
    # Or disable the firewall altogether.
    # Open ports in the firewall.
    firewall.enable = false;
    # firewall.allowedTCPPorts = [ ... ];
    # firewall.allowedUDPPorts = [ ... ];
    defaultGateway = { address = "192.168.1.254"; };
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };
}
