{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.programs.custom-ghostty;
  
  ghosttyPkg = if cfg.prerelease 
               then inputs.ghostty.packages.${pkgs.system}.default 
               else pkgs.ghostty;

  ghosttyConfigFile = "/home/rjpc/.config/ghostty/config";

  ghosttyConfigContent = ''
    # Typography matching early console setup
    font-family = "Terminus (TTF)"
    font-size = 12
    
    # UI and Window Management
    window-padding-x = 10
    window-padding-y = 10
    window-decoration = false
    background-opacity = 0.98
    
    # Fix Delete/Backspace mapping to prevent ^? printing
    keybind = backspace=text:\x7f
    keybind = delete=text:\x1b[3~

    # Vi-mode split navigation
    keybind = ctrl+shift+h=goto_split:left
    keybind = ctrl+shift+j=goto_split:bottom
    keybind = ctrl+shift+k=goto_split:top
    keybind = ctrl+shift+l=goto_split:right

    # macOS-style text resizing
    keybind = super+equal=increase_font_size:1
    keybind = super+minus=decrease_font_size:1
    keybind = super+0=reset_font_size

    # --- INLINE THEME (Habamax Soft White) ---
    background = 1c1c1c
    foreground = e5e5e5
    cursor-color = e5e5e5
    selection-background = 767676
    selection-foreground = 1c1c1c

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
in
{
  options.programs.custom-ghostty = {
    enable = lib.mkEnableOption "Custom Ghostty Terminal Setup";
    
    prerelease = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Switch between stable (nixpkgs) and prerelease (flake main branch).";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [
      terminus_font_ttf
    ];

    environment.systemPackages = [
      ghosttyPkg
    ];

    system.activationScripts.setupGhosttyConfig = ''
      mkdir -p /home/rjpc/.config/ghostty
      cat << 'EOF' > ${ghosttyConfigFile}
      ${ghosttyConfigContent}
      EOF
      chown -R rjpc:users /home/rjpc/.config/ghostty
    '';
  };
}
