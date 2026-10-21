{ pkgs, pkgs_next, ... }:
{
  imports = [ ./development/python.nix ];
  environment.systemPackages =
    with pkgs;
    [
      opencode # LLM CLI - Development
      openssl # maybe for ssl -> wss connection
      wl-clipboard # clipboard tools
      tree-sitter # this is for nvim parsing
      dockerfile-language-server # dockerfile language server
      docker-language-server # nvim docker LSP
      yaml-language-server # nvim LSP
      docker-compose-language-service # docker-compose language server
      # language specifics
      ## go
      go
      gopls # go LSP
      ## c-sharp
      dotnet-sdk
      dotnet-sdk_8
      csharp-ls # csharp lsp
      ## nix
      nixd # nix language server
      nixfmt # nix formatter -> nixfmt
      nil # nix language server
      ## lua
      lua-language-server
      ## shell
      bash-language-server
      ## rust
      rust-analyzer
      rustup
      rustfmt
      rust-analyzer
      ## cpp
      clang-tools # c++/cpp cli tools

      # general dev tooling
      duckdb # duckdb cli - data analysis
    ]
    ++ [
      pkgs_next.pi-coding-agent
    ]; # add ty from the unstable nixpkgs

}
