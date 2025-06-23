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
    hostName = "amdmini-1";
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.1.45"; # fixed manually set ip address
        prefixLength = 24;
      }];
      # macAddress = "84:47:09:59:7d:ca"; # port further from power
      # macAddress = "84:47:09:59:7d:c7"; # port closer to pwoer
    };
  };
}
