{ config, pkgs, pkgs-stable, ... }: {
  hardware.graphics = {
    enable = true;
    # enable32Bit = true; # only really required for gaming
  };

  # required for rocm to work, but also seems to be required for the iGPU to work properly on Ryzen 5000 series APUs
  environment.variables = {
    # This is the magic "trick" for Ryzen 5000 series iGPUs
    HSA_OVERRIDE_GFX_VERSION = "9.0.0";
  };
}
