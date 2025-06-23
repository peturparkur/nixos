{ config, pkgs, ... }: {
  # Unused for now
  fonts.packages = with pkgs; [
    fira-code
    fira-code-symbols
    nerd-fonts.fira-code
  ];
  # console.font = "Cascadia Code";
}
