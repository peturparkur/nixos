{ pkgs, ... }: {
  # https://github.com/Mic92/nix-ld
  programs.nix-ld = { enable = true; };
  programs.nix-ld.libraries = (pkgs.steam-run.args.multiPkgs pkgs)
    ++ [ pkgs.stdenv.cc.cc pkgs.zlib pkgs.libgcc pkgs.umu-launcher];
}
