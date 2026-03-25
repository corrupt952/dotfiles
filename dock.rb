#!/usr/bin/env ruby

def add_app_to_dock(paths)
  paths = Array(paths)
  path = paths.map { |p| File.expand_path(p) }.find { |p| File.exist?(p) }
  unless path
    puts "SKIP: #{paths.join(', ')} not found"
    return
  end

  plist_entry = <<~PLIST
    <dict>
      <key>tile-data</key>
      <dict>
        <key>file-data</key>
        <dict>
          <key>_CFURLString</key>
          <string>#{path}</string>
          <key>_CFURLStringType</key>
          <integer>0</integer>
        </dict>
      </dict>
    </dict>
  PLIST

  system('defaults', 'write', 'com.apple.dock', 'persistent-apps', '-array-add', plist_entry)
  puts "ADD: #{path}"
end

def add_folder_to_dock(path, arrangement: 2, displayas: 0, showas: 0)
  path = File.expand_path(path)
  unless File.directory?(path)
    puts "SKIP: #{path} not found"
    return
  end

  plist_entry = <<~PLIST
    <dict>
      <key>tile-data</key>
      <dict>
        <key>arrangement</key>
        <integer>#{arrangement}</integer>
        <key>displayas</key>
        <integer>#{displayas}</integer>
        <key>file-data</key>
        <dict>
          <key>_CFURLString</key>
          <string>file://#{path}</string>
          <key>_CFURLStringType</key>
          <integer>15</integer>
        </dict>
        <key>file-type</key>
        <integer>2</integer>
        <key>showas</key>
        <integer>#{showas}</integer>
      </dict>
      <key>tile-type</key>
      <string>directory-tile</string>
    </dict>
  PLIST

  system('defaults', 'write', 'com.apple.dock', 'persistent-others', '-array-add', plist_entry)
  puts "ADD: #{path}"
end

# Clear all
system('defaults', 'write', 'com.apple.dock', 'persistent-apps', '-array')
system('defaults', 'write', 'com.apple.dock', 'persistent-others', '-array')
puts "Cleared Dock"

# Apps (Finder is system-pinned, no need to add)
add_app_to_dock '/System/Applications/System Settings.app'
add_app_to_dock '/Applications/1Password.app'
add_app_to_dock '/System/Applications/iPhone Mirroring.app'
add_app_to_dock '/Applications/Discord.app'
add_app_to_dock '/Applications/Obsidian.app'
add_app_to_dock ['/Applications/Vigilare.app', '~/Applications/Vigilare.app']
add_app_to_dock '/Applications/Google Chrome.app'
add_app_to_dock '/Applications/WezTerm.app'
add_app_to_dock '/Applications/Xcode.app'
add_app_to_dock '/Applications/Unity Hub.app'
add_app_to_dock '/Applications/Visual Studio Code.app'
add_app_to_dock '/Applications/Synthesizer V Studio 2 Pro.app'
add_app_to_dock '/Applications/Logic Pro Creator Studio.app'
add_app_to_dock '/Applications/Final Cut Pro Creator Studio.app'
add_app_to_dock '/Applications/Steam.app'
add_app_to_dock '/Applications/ComfyUI.app'

# Folders
add_folder_to_dock '~/Downloads'

# Apply
system('killall', 'Dock')
puts "Dock restarted"
