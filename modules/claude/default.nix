{ config, lib, pkgs, ... }:

let
  configDir = "${config.xdg.configHome}/claude";

  weztermNotifyHook = builtins.replaceStrings
    [
      "@bash@"
      "@date@"
      "@jq@"
      "@mkdir@"
      "@mv@"
    ]
    [
      (lib.getExe pkgs.bash)
      (lib.getExe' pkgs.coreutils "date")
      (lib.getExe pkgs.jq)
      (lib.getExe' pkgs.coreutils "mkdir")
      (lib.getExe' pkgs.coreutils "mv")
    ]
    (builtins.readFile ./wezterm-notify.sh);

  weztermNotifyCommand = "${configDir}/hooks/wezterm-notify.sh";

  notifyHook = {
    hooks = [
      {
        type = "command";
        command = weztermNotifyCommand;
      }
    ];
  };
in
{
  programs.claude-code = {
    enable = true;
    package = null;
    inherit configDir;

    hooks."wezterm-notify.sh" = weztermNotifyHook;
    outputStyles."Global Rules" = ./global-rules.md;

    settings = {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";

      env = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
      };

      permissions = {
        allow = [
          "Bash(git status)"
          "Bash(git log *)"
          "Bash(git diff *)"
          "Bash(git switch *)"
          "Bash(git branch *)"
          "Bash(git fetch *)"
        ];
        deny = [
          "Bash(rm -f *)"
          "Bash(rm -rf *)"
          "Bash(curl *)"
          "Bash(wget *)"
          "Bash(git push -f *)"
          "Bash(git push --force-with-lease *)"
          "Bash(git reset *)"
          "Bash(chmod 777 *)"
          "Bash(npx *)"
          "Bash(pnpx *)"
          "Read(**/.env)"
          "Read(**/.env.*)"
          "Read(**/secrets/**)"
          "Read(**/config/credentials.json)"
          "Read(**/*.pem)"
          "Read(**/*.key)"
        ];
        ask = [
          "Bash(git commit *)"
          "Bash(git push *)"
          "Bash(git rebase *)"
          "Bash(git checkout *)"
        ];
        defaultMode = "default";
      };

      model = "claude-sonnet-5";
      fallbackModel = [
        "claude-opus-4-8"
      ];

      hooks = {
        SessionStart = [ notifyHook ];
        Notification = [ notifyHook ];
        PermissionRequest = [ notifyHook ];
        Elicitation = [ notifyHook ];
        SubagentStop = [ notifyHook ];
        Stop = [
          notifyHook
        ];
        StopFailure = [ notifyHook ];
        SessionEnd = [ notifyHook ];
        UserPromptSubmit = [ ];
        PostToolUse = [
          {
            matcher = "Edit|Write|MultiEdit";
            hooks = [
              {
                type = "command";
                command = "jq -re '.tool_input.file_path | select(endswith(\".swift\"))' | xargs xcrun swift-format --in-place";
                timeout = 10;
              }
            ];
          }
        ];
        PreToolUse = [
          {
            matcher = "WebSearch";
            hooks = [
              {
                type = "command";
                command = "jq -re '.tool_input.query | select(test(\"202[0-4]\"))' > /dev/null && { echo \"Query contains outdated year. Current year is $(date +%Y). Fix it.\" >&2; exit 2; } || exit 0";
                timeout = 5;
              }
            ];
          }
          {
            matcher = "mcp__vigilare__vigilare_get_reminders";
            hooks = [
              {
                type = "command";
                command = "jq -re '.tool_input.filter | select(. == \"all\")' > /dev/null && { echo 'filter \"all\" is not allowed. Use vigilare_get_lists first, then filter by list_id.' >&2; exit 2; } || exit 0";
                timeout = 5;
              }
            ];
          }
          {
            matcher = "mcp__vigilare__vigilare_add_comment";
            hooks = [
              {
                type = "prompt";
                prompt = "The assistant is about to call vigilare_add_comment. Tool call payload is in $ARGUMENTS. vigilare_add_comment appends to a task's append-only conversation log (comments section). The alternative vigilare_update_reminder(notes=...) replaces the task's notes field (persistent task body). Based on the comment content in the payload and the recent conversation context, judge whether add_comment matches the user's actual intent, or whether the assistant likely meant to update the task notes. Output {\"ok\": true} when add_comment is appropriate (e.g., progress log, status update, conversation entry). Output {\"ok\": false, \"reason\": \"<one-sentence reason>, use vigilare_update_reminder(notes=...) instead\"} when the content reads like a body/notes edit (e.g., revising the task description, fixing requirements, restructuring the task definition).";
              }
            ];
          }
        ];
      };

      enabledPlugins = {
        "swift-lsp@claude-plugins-official" = true;
        "frontend-design@claude-plugins-official" = true;
        "labee-standards@labee-standards" = true;
        "document-skills@anthropic-agent-skills" = true;
      };

      extraKnownMarketplaces = {
        labee-standards = {
          source = {
            source = "github";
            repo = "LabeeHive/standards";
          };
          autoUpdate = true;
        };
        anthropic-agent-skills = {
          source = {
            source = "github";
            repo = "anthropics/skills";
          };
          autoUpdate = true;
        };
      };

      outputStyle = "Global Rules";
      language = "日本語";

      voice = {
        enabled = true;
      };

      sandbox = {
        enabled = true;
        autoAllowBashIfSandboxed = true;
        network = {
          allowedDomains = [
            "github.com"
            "api.github.com"
            "*.githubusercontent.com"
            "ghcr.io"
            "formulae.brew.sh"
            "*.npmjs.org"
            "registry.yarnpkg.com"
            "pypi.org"
            "*.pythonhosted.org"
            "rubygems.org"
            "api.rubygems.org"
            "proxy.golang.org"
            "sum.golang.org"
            "pub.dev"
            "cdn.cocoapods.org"
            "packages.unity.com"
            "nuget.org"
            "api.nuget.org"
            "registry-1.docker.io"
            "auth.docker.io"
            "deno.land"
          ];
          allowLocalBinding = true;
        };
        filesystem = {
          allowWrite = [
            "~/.bun"
            "${configDir}/output-styles"
            "~/Obsidian"
            "~/Library/Caches"
          ];
          denyRead = [
            "~/.aws"
            "~/.ssh"
            "~/Workspace/**/.aws"
            "~/Workspace/**/.ssh"
          ];
        };
        enableWeakerNetworkIsolation = true;
        excludedCommands = [
          "docker:*"
          "bun run:*"
          "bun test:*"
          "xcodebuild:*"
          "git push:*"
          "git fetch:*"
        ];
      };

      attribution.sessionUrl = false;
      feedbackSurveyRate = 0;
      spinnerTipsEnabled = false;
      alwaysThinkingEnabled = true;
      effortLevel = "high";
      promptSuggestionEnabled = false;
      awaySummaryEnabled = false;
      autoUpdatesChannel = "latest";
      autoMemoryEnabled = false;
      skipWorkflowUsageWarning = true;
      verbose = true;
      fileCheckpointingEnabled = false;
      remoteControlAtStartup = true;
      agentPushNotifEnabled = true;
      useAutoModeDuringPlan = false;
    };
  };
}
