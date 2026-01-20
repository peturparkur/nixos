{ pkgs, ... }:
let

  # general python packages used by tools
  pythonPackages = ps:
    with ps; [
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
  additionalPythonPackages = ps:
    with ps; [
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

  mypython = with pkgs; [ (python312.withPackages allPythonPackages) ];

in {
  environment.systemPackages = with pkgs;
    [
      openssl # maybe for ssl -> wss connection
      wl-clipboard # clipboard tools
      tree-sitter # this is for nvim parsing
      dockerfile-language-server # dockerfile language server
      docker-language-server # nvim docker LSP
      yaml-language-server # nvim LSP
      docker-compose-language-service # docker-compose language server
      go
      gopls # go LSP
      dotnet-sdk
      dotnet-sdk_8
      csharp-ls # csharp lsp
      nixd # nix language server
      nixfmt-classic # nix formatter -> nixfmt
      nil # nix language server
      lua-language-server
      bash-language-server
      rust-analyzer
      pylyzer
      clang-tools # c++/cpp cli tools
    ] ++ pythonSystemPackages ++ mypython;

}
