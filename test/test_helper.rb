require "minitest/autorun"
require "minitest/spec"

module Kernel
  alias_method :context, :describe
end

def git_root_path
  `git rev-parse --show-toplevel`.chomp
end
