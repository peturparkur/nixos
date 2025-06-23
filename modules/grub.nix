{ ... }: {
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    useOSProber = true;
    memtest86.enable = true; # testing RAM # hardware testing
    efiSupport = true;
    devices = [ "nodev" ];
  };

}
