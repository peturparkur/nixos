{ pkgs, pkgs_next, ... }:
let

  # general python packages used by tools
  pythonPackages =
    ps: with ps; [
      python-lsp-server # python lsp
      python-lsp-ruff # linter
      pylsp-rope
      pylsp-mypy
      debugpy
      pytest

      pydocstyle
      vulture
      mccabe
      pylint
    ];

  # general python packages used day-to-day
  additionalPythonPackages =
    ps: with ps; [
      ipykernel # jupter notebook kernel
      jupyter
      ipython
      pip
      huggingface-hub
      numpy
      requests
      polars
      pyarrow
      pandas
      ray
      uv # faster python package manager
      matplotlib
      # fastapi
      # asyncio
      # torchWithCuda
      pydantic
    ];
  allPythonPackages = ps: pythonPackages ps ++ additionalPythonPackages ps;

  ## python
  pythonSystemPackages = with pkgs; [
    pyright # another python type checker and LSP
    basedpyright # pyright++
    pyrefly

    # Linters
    pylint
    ruff

    poetry
  ];

  mypython = with pkgs; [ (python314.withPackages allPythonPackages) ];

in
{
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
      ## python
      pylyzer
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
      pkgs_next.ty
      pkgs_next.pi-coding-agent
    ] # add ty from the unstable nixpkgs
    ++ pythonSystemPackages
    ++ mypython;

}
