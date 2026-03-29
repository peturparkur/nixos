{
  config,
  networkTopology,
  nodeName,
  ...
}:
{
  imports = [ ./hardware.nix ];
  networking = {
    usePredictableInterfaceNames = false; # to use eth0, eth1, ... interface names; do not use this with multiple network cards
    hostName = nodeName;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = networkTopology.${config.networking.hostName}; # automatically set ip address from flake.nix
          prefixLength = 24;
        }
      ];
      # macAddress = "84:47:09:4a:1e:89"; # port further from power
      # macAddress = "84:47:09:4a:1e:88"; # port closer to power
    };
  };
}
