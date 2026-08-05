_:

{
  programs.opencode = {
    enable = true;
    context = ../agent-rules.md;
  };

  xdg.configFile."opencode/plugins/wezterm-notify.ts".source =
    ./wezterm-notify.ts;
}
