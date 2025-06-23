{ pkgs, ... }: { boot.kernelPackages = pkgs.linuxKernel.packages.linux_5_15; }
