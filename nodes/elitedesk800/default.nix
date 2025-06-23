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
    hostName = "elitedesk800";
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.1.30"; # fixed manually set ip address
        prefixLength = 24;
      }];
    };
  };
}
