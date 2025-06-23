{ pkgs, ... }: { users.users.peter.packages = with pkgs; [ kubectl kubectx ]; }
