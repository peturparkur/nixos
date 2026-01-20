{
  description = "NixOS configuration for x86 home nodes";
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable branch -> most up-to-date
    nixpkgs.url =
      "github:nixos/nixpkgs/nixos-25.11"; # stable branch -> should never crash
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      # manages user specific programs and settings via nixos declarative setup
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland"; # display manager - NOT USED
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    sops-nix = {
      # secrets management - SOPS
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # distributed nixos build + deployment
    colmena = { url = "github:zhaofengli/colmena/main"; };
  };

  outputs = { self, nixpkgs, colmena, home-manager, nixpkgs-unstable, sops-nix
    , ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs-stable = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      baseModules = [
        ./configuration.nix
        ./modules/docker.nix
        ./modules/experimental_features.nix
        ./users/peter
        sops-nix.nixosModules.sops
        ({ ... }: {
          sops.defaultSopsFile = ./secrets/secrets.yaml;
          sops.defaultSopsFormat = "yaml";
          sops.age.keyFile = "/home/peter/.config/sops/age/keys.txt";
        })
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.peter = import ./home/peter/home.nix;
          home-manager.sharedModules =
            [ inputs.sops-nix.homeManagerModules.sops ];
        }
      ];

      # list of shared node modules
      nodeModules = baseModules ++ [ ./kubes/k3s.nix ./networking.nix ];

      MakeNode = nodename: extraModules:
        (_pkgs:
          _pkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs self; };
            modules = [ ./nodes/${nodename} ] ++ extraModules;
          });
    in {
      nixosConfigurations = {
        amdmini-1 = MakeNode "amdmini-1" nodeModules nixpkgs;
        amdmini-2 = MakeNode "amdmini-2" nodeModules nixpkgs;
        elitedesk800 = MakeNode "elitedesk800" nodeModules nixpkgs;

        # this is the only custom made flake since it's not a node
        peter-laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs self;
            inherit pkgs-stable;
            inherit unstable;
          };
          modules = baseModules ++ [
            ./nodes/laptop
            ./modules/grub.nix
            ({ pkgs, ... }:
              let
                user_pkgs = import ./users/extra_packages.nix { inherit pkgs; };
              in {
                config = { }
                  // user_pkgs.enable_additional_user_packages "peter";
              })
            home-manager.nixosModules.home-manager
            {
              home-manager.users.peter = { ... }: {
                imports = [
                  ./home/peter/home.nix
                  ./home/peter/programs/vscode.nix
                  ./home/services/megasync.nix
                ];
              };
            } # semi in
          ];
        };
      };
    };
}
