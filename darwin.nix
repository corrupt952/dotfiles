{ identity, lib, pkgs, ... }:

let
  user = lib.escapeShellArg identity.username;
in
{
  nix = {
    package = pkgs.lix;

    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-older-than 30d";
    };

    optimise = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 4;
          Minute = 15;
        }
      ];
    };

    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nixpkgs.hostPlatform = "aarch64-darwin";

  # `libexec` isn't linked into per-user profiles by default, which breaks
  # `container`'s plugin discovery (apiserver crash-loops on
  # "cannot find any plugins with type network"). See nixpkgs#445648.
  environment.pathsToLink = [ "/libexec" ];

  security.pam.services.sudo_local.touchIdAuth = true;

  users.users.${identity.username} = {
    name = identity.username;
    home = identity.homeDirectory;
  };

  system = {
    primaryUser = identity.username;
    stateVersion = 6;

    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleEnableSwipeNavigateWithScrolls = true;
        ApplePressAndHoldEnabled = false;
        "com.apple.swipescrolldirection" = false;
      };

      menuExtraClock = {
        Show24Hour = true;
        ShowDayOfWeek = false;
        ShowSeconds = false;
      };

      controlcenter = {
        AirDrop = false;
        BatteryShowPercentage = false;
        Bluetooth = false;
        FocusModes = false;
        NowPlaying = false;
        Sound = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
      };

      dock = {
        autohide = true;
        launchanim = false;
        largesize = 64;
        magnification = false;
        mineffect = "scale";
        mru-spaces = false;
        orientation = "bottom";
        show-recents = false;
        tilesize = 64;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      WindowManager.EnableTiledWindowMargins = false;
    };

    activationScripts.postActivation.text = ''
      /usr/bin/killall -qu ${user} Finder || true
      /usr/bin/killall -qu ${user} SystemUIServer || true
    '';
  };
}
