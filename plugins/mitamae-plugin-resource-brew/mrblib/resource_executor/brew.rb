# frozen_string_literal: true

class ::MItamae::Plugin::ResourceExecutor::Brew < ::MItamae::ResourceExecutor::Base
  def apply
    case desired.action
    when :install
      install!
    when :uninstall
      uninstall!
    when :nothing
      # do nothing
    end
  end

  private

  def set_current_attributes(current, desired)
  end

  def set_desired_attributes(desired, action)
  end

  def install!
    return if exist?(desired.name)

    MItamae.logger.info "#{@resource.resource_type}[#{desired.name}] installed will change from 'false' to 'true'"
    @runner.run_command(['brew', 'install', desired.name])
  end

  def uninstall!
    return unless exist?(desired.name)

    MItamae.logger.info "#{@resource.resource_type}[#{desired.name}] installed will change from 'true' to 'false'"
    @runner.run_command(['brew', 'uninstall', desired.name])
  end

  def exist?(name)
    run_command(['brew', 'list', name], error: false).exit_status == 0
  end
end
