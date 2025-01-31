{ lib, config, ... }:

with lib;

let
  userOptions = {
    options.icon = mkOption { type = types.nullOr types.path; default = null; };
  };

  mkGdmUserConf = icon: ''
    [User]
    Session=
    XSession=
    Icon=${icon}
    SystemAccount=false
  '';

  userList = filter (entry: entry.icon != null) (mapAttrsToList (name: value: { inherit name; icon = value.icon; }) config.users.users);

  mkBootCommand = entry: "echo -e '${mkGdmUserConf entry.icon}' > /var/lib/AccountsService/users/${entry.name}\n";

  bootCommands = map mkBootCommand userList;
in

{
  options = {
    users.users = with types; mkOption {
      type = attrsOf (submodule userOptions);
    };
  };

  config = lib.mkIf config.services.xserver.displayManager.gdm.enable {
    boot.postBootCommands = strings.concatStrings bootCommands;
  };
}
