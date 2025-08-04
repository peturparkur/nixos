{ pkgs, ... }: {
  allow_android_packages_user = myuser: {
    programs.adb.enable = true;
    users.users.${myuser}.extraGroups = [ "adbusers" ];
    environment.systemPackages = with pkgs; [
      android-tools
      android-udev-rules
      chromium
    ];
  };
}
