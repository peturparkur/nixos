{
  description = "NixOS configuration for x86 home nodes";
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable branch -> most up-to-date
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05"; # stable branch -> should never crash
    nixpkgs-next.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      # manages user specific programs and settings via nixos declarative setup
      url = "github:nix-community/home-manager/release-26.05";
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
    colmena = {
      url = "github:zhaofengli/colmena/main";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      colmena,
      home-manager,
      nixpkgs-next,
      sops-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs_next = import nixpkgs-next {
        inherit system;
        config.allowUnfree = true;
      };
      networkTopology = {
        elitedesk800 = "192.168.1.30";
        amdmini-1 = "192.168.1.45";
        amdmini-2 = "192.168.1.50";
      };

      garageNodes = {
        amdmini-1 = "69609523a9d7939a37abace4240dde12cc07a43fda2dc8cb5ce67c1931c8b818@192.168.1.45";
        amdmini-2 = "37f26cbac4f1ee7e18f89786fb473bdf1e81365421c14fea987dd8625eb44f7";
      };

      tailscaleNodes = {
        peter-laptop = "tailscale/laptop";
        amdmini-2 = "tailscale/amdmini-2";
      };

      baseModules = [
        ./configuration.nix
        ./modules/docker.nix
        ./modules/experimental_features.nix
        ./pkgs/tailscale.nix
        ./users/peter
        ./modules/zerofs.nix
        ./modules/virtual-filesystem.nix
        ./modules/network-hosts.nix
        sops-nix.nixosModules.sops
        (
          { ... }:
          {
            sops.defaultSopsFile = ./secrets/secrets.yaml;
            sops.defaultSopsFormat = "yaml";
            sops.age.keyFile = "/home/peter/.config/sops/age/keys.txt";
          }
        )
        (
          { ... }:
          {
            services.virtualFs = {
              enable = true;
              mounts.zerofs = {
                protocol = "9p";
                server = "192.168.1.50";
                port = 5564;
                mountPoint = "/mnt/zerofs";
                options = [
                  "version=9p2000.L"
                  "cache=mmap"
                  "access=user"
                ];
              };
            };
          }
        )
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.peter = import ./home/peter/home.nix;
          home-manager.sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
        }
      ];

      # list of shared node modules
      nodeModules = baseModules ++ [
        ./kubes/k3s.nix
        ./networking.nix
        ./modules/nats.nix
      ];

      MakeNode =
        nodename: extraModules:
        (
          _pkgs:
          _pkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs self;
              inherit networkTopology garageNodes tailscaleNodes;
              nodeName = nodename;
            };
            modules = [ ./nodes/${nodename} ] ++ extraModules;
          }
        );
    in
    {
      nixosConfigurations = {
        # adding graphics to amd nodes to allow amdgpu to be used by applications.
        amdmini-1 = MakeNode "amdmini-1" (
          nodeModules
          ++ [
            ./modules/amd_graphics.nix
            ./modules/garage.nix
          ]
        ) nixpkgs;
        amdmini-2 = MakeNode "amdmini-2" (
          nodeModules
          ++ [
            ./modules/amd_graphics.nix
            ./modules/garage.nix
            ./services/zerofs.nix
            # ./services/zerofs_backblaze.nix
            (
              { ... }:
              {
                services.zerofs.garage = {
                  enable = true;
                  cache.memorySizeGb = 8.0;
                  cache.diskSizeGb = 10.0;
                };
                # services.zerofs.backblaze = {
                #   enable = true;
                #   cache.memorySizeGb = 2.0;
                #   cache.diskSizeGb = 2.0;
                # };

                # this would allocate more RAM to iGPU
                # boot.kernelParams = [
                #   "amdgpu.gttsize=16384"
                # ]; # Adjust based on your total RAM})] nixpkgs;
              }
            )
          ]
        ) nixpkgs;
        elitedesk800 = MakeNode "elitedesk800" nodeModules nixpkgs;

        # this is the only custom made flake since it's not a node
        peter-laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs self;
            inherit pkgs_next;
            inherit networkTopology tailscaleNodes;
          };
          modules = baseModules ++ [
            ./nodes/laptop
            ./modules/grub.nix
            (
              { pkgs, ... }:
              let
                user_pkgs = import ./users/extra_packages.nix { inherit pkgs; };
              in
              {
                config = { } // user_pkgs.enable_additional_user_packages "peter";
              }
            )
            # (
            #   { ... }:
            #   {
            #     services.virtualFs = {
            #       enable = true;
            #       mounts.backblaze = {
            #         protocol = "9p";
            #         server = "192.168.1.50";
            #         port = 5565;
            #         mountPoint = "/mnt/backblaze";
            #         options = [
            #           "version=9p2000.L"
            #           "cache=mmap"
            #           "access=user"
            #         ];
            #       };
            #     };
            #   }
            # )
            home-manager.nixosModules.home-manager
            {
              home-manager.users.peter =
                { ... }:
                {
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
