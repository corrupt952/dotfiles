_:

{
  programs.opencode.enable = true;

  xdg.configFile."opencode/plugins/wezterm-notify.ts".source =
    ./wezterm-notify.ts;
}
