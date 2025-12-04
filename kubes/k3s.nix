{ config, pkgs, ... }:
let
  default_flags = [
    # "--tls-san 192.168.1.32"

    # network interface
    "--flannel-iface eth0" # this should be eth0

    ### SERVER CONFIGURATION ###
    "--write-kubeconfig-mode 644" # server config
    # disable pre-packaged components
    "--disable traefik"
    "--disable local-storage"
    "--disable servicelb"

    # kubelet arguments
    # to disable ipv6 and allow some odd all source allowed ipv4
    # "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.conf.all.src_valid_mark,net.ipv6.conf.all.disable_ipv6"
    # "--allowed-unsafe-sysctls=net.ipv4.conf.all.src_valid_mark,net.ipv6.conf.all.disable_ipv6"
  ];
  eth0_addresses = config.networking.interfaces.eth0.ipv4.addresses;
  node_ip = builtins.elemAt eth0_addresses 0;
  k3s_flags = default_flags ++ [ "--node-ip ${node_ip}" ];
in {
  # we want our k3s to support longhorn
  imports = [ ./longhorn.nix ];

  sops.secrets.k3s_token = { };
  services.k3s = {
    enable = true;
    role = "server";
    package = pkgs.k3s_1_33;
    serverAddr = "https://192.168.1.32:6443";
    # configPath = ./config.yaml;
    extraFlags = toString k3s_flags;
    tokenFile = config.sops.secrets.k3s_token.path;
  };
}
