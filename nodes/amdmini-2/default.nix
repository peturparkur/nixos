{ ... }:
# let
#   # This should get overriden by flake.nix
#   hostName = lib.mkDefault "defaultHostName";
# in
{
  imports = [ ./hardware.nix ];
  networking = {
    usePredictableInterfaceNames =
      false; # to use eth0, eth1, ... interface names; do not use this with multiple network cards
    hostName = "amdmini-2";
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.1.50"; # fixed manually set ip address
        prefixLength = 24;
      }];
      # macAddress = "84:47:09:4a:1e:89"; # port further from power
      # macAddress = "84:47:09:4a:1e:88"; # port closer to power
    };
  };
}
