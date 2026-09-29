{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Build the workspace plugin against the Hyprland package from this flake.
  # Hyprland plugins are ABI-sensitive and must not be built against the
  # upstream plugin input's potentially newer Hyprland package.
  splitMonitorWorkspaces = pkgs.stdenv.mkDerivation {
    pname = "split-monitor-workspaces";
    version = "0.55.x";
    src = inputs.split-monitor-workspaces;
    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
    ];
    buildInputs =
      with pkgs;
      [
        hyprland.dev
        pango
        cairo
      ]
      ++ hyprland.buildInputs;
  };

  steamAmd = pkgs.writeShellScriptBin "steam-amd" ''
    # Steam must be fully closed before changing the GPU environment.  If an
    # existing Steam process is running, Steam will reuse it instead.
    exec ${pkgs.coreutils}/bin/env \
      DRI_PRIME=0 \
      __NV_PRIME_RENDER_OFFLOAD=0 \
      __GLX_VENDOR_LIBRARY_NAME=mesa \
      __VK_LAYER_NV_optimus=non_NVIDIA_only \
      NIXOS_OZONE_WL=0 \
      ${pkgs.steam}/bin/steam "$@"
  '';

  gpuUsage = pkgs.writeShellScriptBin "waybar-gpu-usage" ''
    set -eu

    amd="N/A"
    for device in /sys/class/drm/card*/device; do
      if [ -r "$device/vendor" ] && [ "$(cat "$device/vendor")" = "0x1002" ] && [ -r "$device/gpu_busy_percent" ]; then
        amd="$(cat "$device/gpu_busy_percent")"
        break
      fi
    done

    nvidia="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ' || true)"
    [ -n "$nvidia" ] || nvidia="N/A"

    printf '{"text":"GPU %s%% / %s%%","tooltip":"AMD iGPU: %s%%\\nNVIDIA dGPU: %s%%"}\n' \
      "$amd" "$nvidia" "$amd" "$nvidia"
  '';

  diskIo = pkgs.writeShellScriptBin "waybar-disk-io" ''
    set -u

    state="/tmp/waybar-disk-io-$(id -u)"
    now="$(date +%s%N)"
    read_sectors=0
    write_sectors=0

    for stat in /sys/block/*/stat; do
      device="''${stat%/stat}"
      name="''${device##*/}"
      case "$name" in
        loop*|ram*|zram*|dm-*) continue ;;
      esac
      [ -r "$stat" ] || continue
      values=( $(cat "$stat") )
      read_sectors=$((read_sectors + values[2]))
      write_sectors=$((write_sectors + values[6]))
    done

    previous_time=0
    previous_read=0
    previous_write=0
    if [ -r "$state" ]; then
      read -r previous_time previous_read previous_write < "$state" || true
    fi

    delta_time=$((now - previous_time))
    delta_read=$((read_sectors - previous_read))
    delta_write=$((write_sectors - previous_write))
    [ "$delta_time" -gt 0 ] || delta_time=1
    [ "$delta_read" -ge 0 ] || delta_read=0
    [ "$delta_write" -ge 0 ] || delta_write=0

    read_rate="$(awk -v sectors="$delta_read" -v ns="$delta_time" \
      'BEGIN { printf "%.1f", sectors * 512 / ns * 1000 }')"
    write_rate="$(awk -v sectors="$delta_write" -v ns="$delta_time" \
      'BEGIN { printf "%.1f", sectors * 512 / ns * 1000 }')"

    printf '%s %s %s\n' "$now" "$read_sectors" "$write_sectors" > "$state"
    printf '{"text":"R %s MB/s W %s MB/s","tooltip":"Disk read: %s MB/s\\nDisk write: %s MB/s"}\n' \
      "$read_rate" "$write_rate" "$read_rate" "$write_rate"
  '';

  helpText = pkgs.writeText "hyprland-keybindings.txt" ''
    HYPRLAND QUICK HELP
    ===================
    The Super key is the Windows/Command key.  Press Super+F1 at any time to
    open this list.  Escape closes a launcher or help window.

    START HERE
    Super+T             Open a terminal
    Super+D             Open the application launcher
    Super+F1            Show this help
    Super+F2            Open system settings
    Super+F3            Open monitor/display settings
    Super+Shift+N       Edit network connections (nm-connection-editor)
    Super+Alt+L          Lock the screen
    Super+Shift+Q             Exit Hyprland

    WINDOWS AND TILING
    Super+Arrow         Focus the window in that direction
    Super+H/J/K/L       Focus left/down/up/right (vim-style)
    Super+, / Super+.   Focus the monitor to the left/right
    Super+Shift+, / .   Move the active window to the left/right monitor
    Super+Shift+Arrow   Move the active window
    Super+Shift+H/J/K/L Move the active window (vim-style)
    Super+Ctrl+Arrow    Resize the active window
    Super+Left drag     Move a floating window with the mouse
    Super+Right drag    Resize a floating window with the mouse
    Super+W             Close the active window
    Super+V             Toggle floating for the active window
    Super+F             Toggle fullscreen
    Super+P             Toggle pseudotiling
    Super+S             Toggle split direction

    WORKSPACES (INDEPENDENT PER SCREEN)
    Super+1 .. Super+9 / Super+0              Switch local workspace 1 .. 10
    Super+Shift+1 .. +9 / +0                  Move to local workspace 1 .. 10
    Super+E                                    Switch to the first empty local workspace
    Super+Shift+E                              Move to the first empty local workspace
    Super+PageUp / Super+PageDown              Previous/next local workspace
    Super+Tab                                  Cycle focus between windows

    EVERYDAY CONTROLS
    Super+Shift+S        Select an area and copy a screenshot
    Lower+Printscreen    Select an area and copy a screenshot
    Super+Escape         Toggle mute
    Super+Shift+V        Open the audio input/output controls
    Volume keys          Change volume / mute
    Brightness keys      Change screen brightness
    Super+Shift+R        Reload Hyprland

    The top bar shows workspaces, the current time, network, Bluetooth,
    volume, brightness, battery and tray status.  Click the network or
    Bluetooth indicator to open its settings.

    The tray contains the NetworkManager applet.  Use it to switch between
    Ethernet and Wi-Fi, join or forget networks, and connect to hidden SSIDs
    while travelling.  Super+Shift+N opens the full connection editor.
  '';

  helpScript = pkgs.writeShellScriptBin "hyprland-help" ''
    set -eu
    ${pkgs.coreutils}/bin/cat ${helpText} | ${pkgs.wofi}/bin/wofi \
      --show dmenu \
      --prompt 'Hyprland keybindings' \
      --width 760 \
      --height 620 \
      --cache-file /dev/null
  '';

  screenshotScript = pkgs.writeShellScriptBin "hyprland-screenshot" ''
    set -eu
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy
    ${pkgs.libnotify}/bin/notify-send "Screenshot copied" "The selected area is in the clipboard."
  '';
in
{
  home.packages = with pkgs; [
    grim
    helpScript
    hypridle
    hyprlock
    mako
    screenshotScript
    steamAmd
    gpuUsage
    diskIo
  ];

  # delta and difftastic are installed in the laptop's system profile.  Git
  # can therefore use them without Home Manager adding duplicate user copies.
  programs.git.settings = {
    core.pager = "delta";
    interactive.diffFilter = "delta --color-only";
    pager = {
      blame = "delta";
      diff = "delta";
      log = "delta";
      show = "delta";
    };
    delta = {
      navigate = true;
      "side-by-side" = true;
      "line-numbers" = true;
      "hunk-header-style" = "file line-number syntax";
      "file-style" = "bold yellow";
      "file-decoration-style" = "none";
      "whitespace-error-style" = "22 reverse";
    };
    alias = {
      dft = "!git -c diff.external=difft diff --ext-diff";
      dft-cached = "!git -c diff.external=difft diff --cached --ext-diff";
      dft-show = "!git -c diff.external=difft show --ext-diff";
    };
  };

  home.sessionVariables = {
    DFT_DISPLAY = "side-by-side";
    DFT_COLOR = "always";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    # Hyprland is installed by the NixOS module.  Avoid installing a second
    # copy through Home Manager, which also keeps the session and portal in
    # sync with the system package.
    package = null;
    portalPackage = null;
    plugins = [ splitMonitorWorkspaces ];
    settings = {
      plugin = {
        "split-monitor-workspaces" = {
          # Ten independently numbered workspaces are available on each
          # monitor; empty ones are created/selected as needed.
          count = 10;
          keep_focused = 1;
          enable_notifications = 0;
          enable_persistent_workspaces = 1;
          enable_wrapping = 1;
          link_monitors = 0;
          monitor_priority = "eDP-1, DP-4";
        };
      };
      "$mainMod" = "SUPER";

      monitor = [ ", preferred, auto, 1" ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        accel_profile = "flat";
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          disable_while_typing = true;
          clickfinger_behavior = true;
          scroll_factor = 1.0;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
        "col.active_border" = "rgba(89b4faee) rgba(cba6f7ee) 45deg";
        "col.inactive_border" = "rgba(45475aaa)";
      };

      decoration = {
        rounding = 8;
        active_opacity = 1.0;
        inactive_opacity = 0.95;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(11111bee)";
        };
        blur = {
          enabled = true;
          size = 3;
          passes = 2;
        };
      };

      animations = {
        enabled = true;
        bezier = "easeOutQuint,0.23,1,0.32,1";
        animation = [
          "windows, 1, 4, easeOutQuint"
          "windowsOut, 1, 4, easeOutQuint, popin 80%"
          "border, 1, 5, default"
          "fade, 1, 4, easeOutQuint"
          "workspaces, 1, 4, easeOutQuint"
        ];
      };

      dwindle = {
        preserve_split = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      # Start the desktop helpers when this session starts.  They are kept in
      # exec-once rather than a shell profile so they also work from GDM.
      "exec-once" = [
        # Home Manager loads the plugin via its generated exec-once entry.
        # Reload once after that entry so the plugin-provided dispatchers are
        # registered before Hyprland validates the workspace keybindings.
        "hyprctl reload"
        "waybar"
        "udiskie --automount --notify --tray"
        "nm-applet"
        "mako"
        "swaybg -c '#1e1e2e'"
      ];

      bind = [
        # T and D are deliberately used instead of Return/Space: they are
        # easier to press on a split keyboard with thumb modifiers.
        "$mainMod, T, exec, kitty"
        "$mainMod, D, exec, wofi --show drun --prompt Applications"
        "$mainMod, F1, exec, hyprland-help"
        "$mainMod, F2, exec, gnome-control-center"
        "$mainMod, F3, exec, nwg-displays"
        "$mainMod SHIFT, N, exec, nm-connection-editor"
        "$mainMod ALT, L, exec, hyprlock"
        "$mainMod SHIFT, Q, exit"
        "$mainMod, W, killactive"
        "$mainMod, V, togglefloating"
        "$mainMod, F, fullscreen"
        "$mainMod, P, pseudo"
        "$mainMod, S, layoutmsg, togglesplit"
        "$mainMod, TAB, cyclenext"
        "$mainMod SHIFT, R, exec, hyprctl reload"

        # Directional focus: both arrows and the familiar vim keys.
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, u"
        "$mainMod, J, movefocus, d"
        "$mainMod, comma, focusmonitor, l"
        "$mainMod, period, focusmonitor, r"
        "$mainMod SHIFT, comma, movewindow, mon:l"
        "$mainMod SHIFT, period, movewindow, mon:r"

        # Move the active window.
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"
        "$mainMod SHIFT, H, movewindow, l"
        "$mainMod SHIFT, L, movewindow, r"
        "$mainMod SHIFT, K, movewindow, u"
        "$mainMod SHIFT, J, movewindow, d"

        # The plugin makes these IDs local to whichever monitor is focused.
        # Each monitor can therefore have workspace 1, workspace 2, etc.
        "$mainMod, 1, split-workspace, 1"
        "$mainMod, 2, split-workspace, 2"
        "$mainMod, 3, split-workspace, 3"
        "$mainMod, 4, split-workspace, 4"
        "$mainMod, 5, split-workspace, 5"
        "$mainMod, 6, split-workspace, 6"
        "$mainMod, 7, split-workspace, 7"
        "$mainMod, 8, split-workspace, 8"
        "$mainMod, 9, split-workspace, 9"
        "$mainMod, 0, split-workspace, 10"
        "$mainMod SHIFT, 1, split-movetoworkspacesilent, 1"
        "$mainMod SHIFT, 2, split-movetoworkspacesilent, 2"
        "$mainMod SHIFT, 3, split-movetoworkspacesilent, 3"
        "$mainMod SHIFT, 4, split-movetoworkspacesilent, 4"
        "$mainMod SHIFT, 5, split-movetoworkspacesilent, 5"
        "$mainMod SHIFT, 6, split-movetoworkspacesilent, 6"
        "$mainMod SHIFT, 7, split-movetoworkspacesilent, 7"
        "$mainMod SHIFT, 8, split-movetoworkspacesilent, 8"
        "$mainMod SHIFT, 9, split-movetoworkspacesilent, 9"
        "$mainMod SHIFT, 0, split-movetoworkspacesilent, 10"
        "$mainMod, E, split-workspace, empty"
        "$mainMod SHIFT, E, split-movetoworkspacesilent, empty"
        "$mainMod, PAGEUP, split-workspace, -1"
        "$mainMod, PAGEDOWN, split-workspace, +1"

        # An interactive region screenshot copied to the clipboard.  The
        # Super+Shift binding is convenient on the Glove80; the Print key is
        # retained for the Lower-layer hardware shortcut.
        "$mainMod SHIFT, S, exec, hyprland-screenshot"
        ", PRINT, exec, hyprland-screenshot"
        "$mainMod, ESCAPE, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        "$mainMod SHIFT, V, exec, pavucontrol"
      ];

      # Mouse support for floating windows.  Normal pointer clicks and
      # touchpad gestures work without a modifier.
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      # Resize with Super+Ctrl and repeated key presses.
      binde = [
        "$mainMod CTRL, left, resizeactive, -40 0"
        "$mainMod CTRL, right, resizeactive, 40 0"
        "$mainMod CTRL, up, resizeactive, 0 -40"
        "$mainMod CTRL, down, resizeactive, 0 40"
        "$mainMod CTRL, H, resizeactive, -40 0"
        "$mainMod CTRL, L, resizeactive, 40 0"
        "$mainMod CTRL, K, resizeactive, 0 -40"
        "$mainMod CTRL, J, resizeactive, 0 40"
      ];

      # Media keys should also work while a normal application has focus.
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
      bindl = [
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
    };

    # nwg-displays writes mutable monitor rules here.  Keep this separate from
    # the Home Manager-generated hyprland.conf so the GUI can save changes.
    extraConfig = "source = ~/.config/hypr/monitors.conf";
  };

  # Wofi and other application launchers discover this .desktop entry.  It
  # leaves the normal Steam launcher untouched and makes the tested AMD-iGPU
  # path explicit.
  xdg.desktopEntries.steam-amd = {
    name = "Steam (AMD iGPU)";
    genericName = "Game launcher";
    exec = "${steamAmd}/bin/steam-amd %U";
    icon = "steam";
    terminal = false;
    categories = [ "Game" ];
  };

  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 32;
        spacing = 6;
        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "cpu"
          "custom/gpu"
          "disk"
          "custom/disk-io"
          "network"
          "bluetooth"
          "pulseaudio"
          "backlight"
          "battery"
          "tray"
        ];

        "hyprland/workspaces" = {
          disable-scroll = true;
          all-outputs = false;
          format = "{name}";
        };
        "hyprland/window" = {
          max-length = 55;
          separate-outputs = true;
        };
        clock = {
          interval = 1;
          format = "{:%a %d %b  %H:%M}";
          tooltip-format = "<big>{:%B %Y}</big>\n<tt>{calendar}</tt>";
        };
        cpu = {
          interval = 2;
          format = "CPU {usage}%";
          states = {
            warning = 70;
            critical = 90;
          };
          tooltip-format = "CPU usage: {usage}%";
        };
        "custom/gpu" = {
          interval = 2;
          return-type = "json";
          exec = "waybar-gpu-usage";
          format = "{text}";
          tooltip = true;
        };
        disk = {
          path = "/";
          interval = 30;
          format = "Disk {percentage_used}%";
          states = {
            warning = 80;
            critical = 90;
          };
          tooltip-format = "{used} used of {total} ({percentage_used}%)";
        };
        "custom/disk-io" = {
          interval = 2;
          return-type = "json";
          exec = "waybar-disk-io";
          format = "{text}";
          tooltip = true;
        };
        network = {
          interval = 2;
          format-wifi = "  {signalStrength}% ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
          format-ethernet = "󰈀  {ifname} ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
          format-disconnected = "󰤮  Offline";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}\n{essid}\n↓ {bandwidthDownBytes} ↑ {bandwidthUpBytes}";
          on-click = "nm-connection-editor";
        };
        bluetooth = {
          format = " Off";
          format-disabled = " Off";
          format-connected = " {num_connections}";
          format-connected-battery = " {device_battery_percentage}%";
          tooltip-format = "{controller_alias}\n{device_alias}\n{num_connections} connected";
          on-click = "blueman-manager";
        };
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟 Muted";
          format-icons = {
            default = [
              ""
              ""
              ""
            ];
          };
          scroll-step = 5;
          on-click = "pavucontrol";
          on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          tooltip-format = "{desc} / {volume}%";
        };
        backlight = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
        };
        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󰚥 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          format-time = "{H}h {M}m";
          tooltip-format = "{capacity}% — {time} remaining\n{power:.1f} W";
        };
        tray = {
          spacing = 8;
        };
      }
    ];

    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "Adwaita Sans", "Noto Sans", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.94);
        color: #cdd6f4;
      }

      #workspaces button,
      #window,
      #clock,
      #cpu,
      #custom-gpu,
      #disk,
      #custom-disk-io,
      #network,
      #bluetooth,
      #pulseaudio,
      #backlight,
      #battery,
      #tray {
        padding: 0 5px;
      }

      /* Reserve space for changing values so the bar does not jitter as
         byte units and percentages gain or lose digits.

         These minima were checked against mock longest labels at the current
         13px font size, including the shared 5px left/right padding:
           clock:      "Sun 27 Sep  23:59"             -> 135px
           CPU:        "CPU 100%"                      -> 70px
           GPU:        "GPU 100% / 100%"               -> 125px
           disk:       "Disk 100%"                     -> 80px
           disk I/O:   "R 999.9 MB/s W 999.9 MB/s"     -> 190px
           network:    " 100% ↓999.9MB/s ↑999.9MB/s"  -> 245px
           Bluetooth:  " 100%"                       -> 72px
           volume:     " 100%"                        -> 76px
           brightness: "󰃠 100%"                        -> 70px
           battery:    "󰁹 100%"                        -> 76px

         Keep these examples in sync if a module's visible format changes.
         The tray is intentionally variable because its icon count changes. */
      #clock {
        min-width: 135px;
      }
      #cpu {
        min-width: 70px;
      }
      #custom-gpu {
        min-width: 125px;
      }
      #disk {
        min-width: 80px;
      }
      #custom-disk-io {
        min-width: 190px;
      }
      #network {
        min-width: 245px;
      }
      #bluetooth {
        min-width: 72px;
      }
      #pulseaudio {
        min-width: 76px;
      }
      #backlight {
        min-width: 70px;
      }
      #battery {
        min-width: 76px;
      }

      #clock, #cpu, #custom-gpu, #disk, #custom-disk-io,
      #network, #bluetooth, #pulseaudio, #backlight, #battery {
        font-feature-settings: "tnum";
      }

      #workspaces button {
        color: #6c7086;
        background: transparent;
      }

      #workspaces button.active {
        color: #cba6f7;
        background: #313244;
      }

      #workspaces button:hover {
        background: #45475a;
      }

      #clock {
        color: #f5c2e7;
        font-weight: bold;
      }

      #cpu { color: #cba6f7; }
      #custom-gpu { color: #f5c2e7; }
      #disk, #custom-disk-io { color: #fab387; }
      #network, #bluetooth { color: #89dceb; }
      #pulseaudio { color: #a6e3a1; }
      #backlight { color: #f9e2af; }
      #battery { color: #fab387; }
      #battery.warning { color: #f9e2af; }
      #battery.critical { color: #f38ba8; }
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      anchor = "top-right";
      background-color = "#1e1e2eee";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 2;
      border-radius = 8;
      default-timeout = 5000;
      font = "Adwaita Sans 11";
      width = 360;
      margin = 12;
      padding = "10";
      icons = true;
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };
      background = [
        {
          monitor = "";
          color = "rgb(30, 30, 46)";
        }
      ];
      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          color = "rgb(205, 214, 244)";
          position = "0, 80";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "Welcome, $USER";
          font_size = 18;
          color = "rgb(166, 173, 200)";
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
      "input-field" = [
        {
          monitor = "";
          size = "280, 50";
          position = "0, -100";
          dots_center = true;
          fade_on_empty = false;
          inner_color = "rgb(49, 50, 68)";
          outer_color = "rgb(137, 180, 250)";
          outline_thickness = 2;
          placeholder_text = "Password...";
          font_color = "rgb(205, 214, 244)";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # HYPRLAND_INSTANCE_SIGNATURE is imported by the Hyprland session target,
  # but is not present in GNOME.  This keeps the shared Home Manager profile
  # from starting Hypridle in the GNOME fallback session.
  systemd.user.services.hypridle.Unit.ConditionEnvironment =
    lib.mkForce "HYPRLAND_INSTANCE_SIGNATURE";

  # Ensure the source file exists before Hyprland starts.  It is deliberately
  # not a home.file entry: nwg-displays must be able to update it later.
  home.activation.ensureHyprMonitorConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/hypr/monitors.conf" ]; then
      install -Dm644 /dev/null "$HOME/.config/hypr/monitors.conf"
    fi
  '';

  home.file.".config/hypr/keybindings.txt".source = helpText;
}
