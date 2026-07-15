{ lib, pkgs, ... }:

let
  tmuxKubectl = pkgs.writeShellApplication {
    name = "tmux-kubectl";
    text = builtins.readFile ./kubectl.sh;
  };
in
{
  home.file.".local/bin/tmux-kubectl".source = lib.getExe tmuxKubectl;

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    escapeTime = 100;
    keyMode = "vi";
    mouse = true;
    terminal = "xterm-256color";

    extraConfig = ''
      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e'"
      set-option -g renumber-windows on

      set-option -g status-style bg=default,fg=colour253
      set-window-option -g xterm-keys on
      set-window-option -g window-status-style fg=default,bg=default
      set-window-option -g window-status-current-style fg=colour178,bg=default
      set-option -g status-left "#[fg=colour251]%Y/%m/%d %H:%M:%S"
      set-option -g status-right "#[fg=colour33]#(${lib.getExe tmuxKubectl}) #[fg=green][#S:#I.#P]"
      set-option -g status-position bottom
      set-option -g status on
      set-option -g status-interval 1
      set-option -g status-justify centre
      set-option -g status-left-length 60
      set-option -g status-right-length 90

      bind r source-file ~/.config/tmux/tmux.conf

      unbind -T copy-mode-vi Enter
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
    '';
  };
}
