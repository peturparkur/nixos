{ lib, pkgs, ... }:
let
  # After creating the home cache, replace null with the complete public key
  # reported by `attic cache info local:home`. Never put a private key here.
  atticPublicKey = "home:GlryjNVuuc9cal9xKp8hRCnry9DlHkyFYAXiMPQr+Fk=";
in
{
  nix.settings = {
    extra-substituters = [
      "http://cache.home.arpa?priority=30"
    ]
    ++ lib.optional (atticPublicKey != null) "http://attic.home.arpa/home?priority=20";

    extra-trusted-public-keys = lib.optional (atticPublicKey != null) atticPublicKey;

    # The laptop must still build when these LAN-only endpoints are unreachable.
    connect-timeout = lib.mkDefault 3;
  };

  environment.systemPackages = [ pkgs.attic-client ];
}
