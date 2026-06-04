{ pkgs, ... }:
{

  environment.systemPackages = [ pkgs.zerofs ];

  # Redis instance for zerofs
  users.users.zerofs = {
    isSystemUser = true;
    group = "zerofs";
  };
  users.groups.zerofs = { };
  services.redis.servers.zerofs = {
    user = "zerofs";
    enable = true;
    port = 6380; # 1 off from default redis port
  };
}
