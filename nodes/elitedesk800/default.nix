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
  };
  networking.interfaces.eth0 = {
    ipv4.addresses = [
      {
        # automatically set ip address from flake.nix
        address = networkTopology.${config.networking.hostName};
        prefixLength = 24;
      }
    ];
  };
}
