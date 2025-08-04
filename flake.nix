{
  description = "NixOS configuration for x86 home nodes";
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable branch -> most up-to-date
    nixpkgs.url =
      "github:nixos/nixpkgs/nixos-25.05"; # stable branch -> should never crash
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      # manages user specific programs and settings via nixos declarative setup
      url = "github:nix-community/home-manager/release-25.05";
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
      # pkgs = import nixpkgs {
      #   inherit system;
      #   config.allowUnfree = true;
      # };
      # nixpkgs = import nixpkgs {
      #   inherit system;
      #   config.allowUnfree = true;
      # };
      pkgs-stable = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      # list of shared node modules
      nodeModules = [
        ./configuration.nix
        ./networking.nix
        ./kubes/k3s.nix
        ./modules/docker.nix
        ./modules/experimental_features.nix
        ./users/peter
        sops-nix.nixosModules.sops
        ({ ... }: {
          sops.defaultSopsFile = ./secrets/secrets.yaml;
          sops.defaultSopsFormat = "yaml";
        })
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.peter = import ./home/peter/home.nix;
        }
      ];

      MakeNode = nodename: extraModules:
        (_pkgs:
          _pkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = import _pkgs {
              system = "x86_64-linux";
              inherit inputs self;
              config.allowUnfree = true;
            };
            modules = [ ./nodes/${nodename} ] ++ extraModules;
          });
    in {
      nixosConfigurations = {
        # amdmini-1 = MakeNode "amdmini-1" nodeModules nixpkgs;
        amdmini-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./nodes/amdmini-1 ] ++ nodeModules;
        };
        # amdmini-2 = MakeNode "amdmini-2" nodeModules nixpkgs;
        amdmini-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./nodes/amdmini-2 ] ++ nodeModules;
        };
        # elitedesk800 = MakeNode "elitedesk800" nodeModules nixpkgs;
        elitedesk800 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./nodes/elitedesk800 ] ++ nodeModules;
        };
        peter-laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs self;
            inherit pkgs-stable;
            inherit unstable;
          };
          modules = [ ./nodes/laptop ] ++ [
            ./configuration.nix
            ./modules/grub.nix
            ./modules/experimental_features.nix
            ./users/peter
            ({ pkgs, ... }:
              let
                user_pkgs = import ./users/extra_packages.nix { inherit pkgs; };
              in {
                config = { }
                  // user_pkgs.enable_additional_user_packages "peter";
              })
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
              home-manager.users.peter = { ... }: {
                imports = [
                  ./home/peter/home.nix
                  ./home/peter/programs/vscode.nix
                  ./home/services/megasync.nix
                ];
              };
            }
          ];
        };
      };
    };
}
