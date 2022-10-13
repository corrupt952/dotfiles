require "minitest/autorun"
require "minitest/spec"

module Kernel
  alias_method :context, :describe
end

def git_root_path
  `git rev-parse --show-toplevel`.chomp
end

def config_root_path
  File.join(git_root_path, 'config')
end
