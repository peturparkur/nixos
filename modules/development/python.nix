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
    pyrefly

    # Linters
    pylint
    ruff

    poetry
  ];

  mypython = with pkgs; [ (python314.withPackages allPythonPackages) ];
in
{
  environment.systemPackages = [
    ## python
    pkgs.pylyzer
    pkgs_next.ty
  ]
  ++ pythonSystemPackages
  ++ mypython;

}
