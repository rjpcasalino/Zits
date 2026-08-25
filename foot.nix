{ config, pkgs, ... }:

{
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=12.5

    [cursor]
    blink=yes

    [colors-dark]
    # Midnight 2026 Prompt Vibe (Cool Soft Black / Muted Pastels)
    # Extracted from your shell.nix starship configuration
    cursor=141417 7e9cd8
    background=141417
    foreground=d0d0d8

    # Normal colors
    regular0=1c1c22 # black
    regular1=d97c8a # red (Muted Rose)
    regular2=8abf9c # green (Muted Mint)
    regular3=d4b47b # yellow (Soft Gold)
    regular4=7e9cd8 # blue (Powder Blue)
    regular5=b893ce # magenta (Dusty Lavender)
    regular6=78b5ba # cyan (Soft Cyan)
    regular7=a0a0ab # white

    # Bright colors
    bright0=68687a # bright black (Muted Slate)
    bright1=e38e9a # bright red (lighter rose)
    bright2=9ecfbc # bright green (lighter mint)
    bright3=e6c891 # bright yellow (lighter gold)
    bright4=90aee6 # bright blue (lighter powder blue)
    bright5=c6a3db # bright magenta (lighter lavender)
    bright6=8bc6cb # bright cyan (lighter cyan)
    bright7=d0d0d8 # bright white

    [key-bindings]
    # macOS-style font resizing (Command / Mod4 + = / + / - / 0) alongside standard Ctrl bindings
    font-increase=Control+plus Control+equal Control+KP_Add Mod4+plus Mod4+equal Mod4+KP_Add
    font-decrease=Control+minus Control+KP_Subtract Mod4+minus Mod4+KP_Subtract
    font-reset=Control+0 Control+KP_0 Mod4+0 Mod4+KP_0
  '';

  system.activationScripts.setupFootConfig = ''
    mkdir -p /home/rjpc/.config/foot
    ln -sf /etc/xdg/foot/foot.ini /home/rjpc/.config/foot/foot.ini
    chown -R rjpc:users /home/rjpc/.config/foot
  '';
}
