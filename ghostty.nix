{ config, pkgs, ... }:

{
  # Expose the TrueType version of Terminus to fontconfig so Ghostty can see it
  fonts.packages = with pkgs; [
    terminus_font_ttf
  ];

  environment.systemPackages = [
    (pkgs.symlinkJoin {
      name = "ghostty-wrapped";
      paths = [ pkgs.ghostty ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/ghostty \
          --add-flags "--config-file=/etc/xdg/ghostty/config"
      '';
    })
  ];

   environment.etc."xdg/ghostty/config".text = ''
    # Typography matching early console setup
    font-family = "Terminus (TTF)"
    font-size = 12 
    # UI and Window Management
    window-padding-x = 10
    window-padding-y = 10
    window-decoration = false
    background-opacity = 0.98
    
    # Vi-mode split navigation (Shift added to preserve shell shortcuts)
    keybind = ctrl+shift+h=goto_split:left
    keybind = ctrl+shift+j=goto_split:bottom
    keybind = ctrl+shift+k=goto_split:top
    keybind = ctrl+shift+l=goto_split:right

    # macOS-style text resizing (adjusted by 1 point per keystroke)
    keybind = super+equal=increase_font_size:1
    keybind = super+minus=decrease_font_size:1
    keybind = super+0=reset_font_size


    # --- INLINE THEME (Habamax Phosphor) ---
    background = 1c1c1c
    foreground = 87d787
    cursor-color = 87d787
    selection-background = 767676
    selection-foreground = 1c1c1c

    # Habamax-aligned palette mapping
    palette = 0=#1c1c1c
    palette = 1=#af5f5f
    palette = 2=#5faf5f
    palette = 3=#af875f
    palette = 4=#5f87af
    palette = 5=#af87af
    palette = 6=#5f8787
    palette = 7=#9e9e9e
    palette = 8=#767676
    palette = 9=#d75f87
    palette = 10=#87d787
    palette = 11=#d7af87
    palette = 12=#5fafd7
    palette = 13=#d787d7
    palette = 14=#87afaf
    palette = 15=#c7c7c7
  '';
}
