# frozen_string_literal: true

class ::MItamae::Plugin::Resource::Brew < ::MItamae::Resource::Base
  define_attribute :name, type: String, default_name: true
  define_attribute :action, default: :install
  define_attribute :options, type: Array, default: []

  self.available_actions = [:install, :uninstall, :nothing]
end
