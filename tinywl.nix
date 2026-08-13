{ config, pkgs, lib, ... }:

let

  tinywl = pkgs.stdenv.mkDerivation {
    pname = "tinywl";
    version = pkgs.wlroots.version;

    src = pkgs.wlroots.src;

    sourceRoot = "source/tinywl";

    nativeBuildInputs = with pkgs; [
      pkg-config
      wayland-scanner
      gnumake
    ];

    buildInputs = with pkgs; [
      wlroots
      wayland
      wayland-protocols
      libxkbcommon
      pixman
    ];

    postPatch = ''
      # 1. Include unistd.h at the top of the file for fork() and execl()
      sed -i '1s/^/#include <unistd.h>\n/' tinywl.c

      # 2. Update the modifier check to support both standard PC (Ctrl+Alt) 
      # and Mac-style (Cmd+Option / Logo+Alt) layouts
      substituteInPlace tinywl.c \
        --replace-fail 'if ((modifiers & WLR_MODIFIER_ALT) &&' \
                       'uint32_t pc_mods = WLR_MODIFIER_CTRL | WLR_MODIFIER_ALT;
                        uint32_t mac_mods = WLR_MODIFIER_LOGO | WLR_MODIFIER_ALT;
                        if (((modifiers & pc_mods) == pc_mods || (modifiers & mac_mods) == mac_mods) &&'

      # 3. Inject our custom cwm keybindings (with the updated toplevels logic)
      substituteInPlace tinywl.c \
        --replace-fail 'case XKB_KEY_Escape:' \
                       'case XKB_KEY_q:
                wl_display_terminate(server->wl_display);
                break;
        case XKB_KEY_Return:
                if (fork() == 0) {
                        execl("${pkgs.foot}/bin/foot", "foot", (char *) NULL);
                }
                break;
        case XKB_KEY_x:
                if (!wl_list_empty(&server->toplevels)) {
                        struct tinywl_toplevel *current_toplevel = wl_container_of(server->toplevels.next, current_toplevel, link);
                        wlr_xdg_toplevel_send_close(current_toplevel->xdg_toplevel);
                }
                break;
        case XKB_KEY_Escape:'
    '';

    buildPhase = ''
      runHook preBuild
      make
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp tinywl $out/bin/
      runHook postInstall
    '';
  };

  # Create an executable launcher script that opens a foot window on initial startup
  start-tinywl = pkgs.writeShellScriptBin "start-tinywl" ''
    exec ${tinywl}/bin/tinywl -s ${pkgs.foot}/bin/foot
  '';
in
{
  environment.systemPackages = [
    tinywl
    start-tinywl
    pkgs.foot
  ];

  services.displayManager.sessionPackages = [
    (pkgs.runCommand "tinywl-session" {
      passthru.providedSessions = [ "tinywl" ];
    } ''
      mkdir -p $out/share/wayland-sessions
      cat > $out/share/wayland-sessions/tinywl.desktop <<EOF
      [Desktop Entry]
      Name=TinyWL
      Comment=A minimal Wayland compositor
      Exec=${start-tinywl}/bin/start-tinywl
      Type=Application
      EOF
    '')
  ];

}
