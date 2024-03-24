# frozen_string_literal: true

class ::MItamae::Plugin::Resource::Symlink < ::MItamae::Resource::Base
  define_attribute :path, type: String, default_name: true
  define_attribute :action, type: Symbol, default: :create
  define_attribute :source, type: String
  define_attribute :force, type: [TrueClass, FalseClass], default: false

  self.available_actions = [:create, :delete, :nothing]
end
