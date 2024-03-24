# frozen_string_literal: true

class ::MItamae::Plugin::ResourceExecutor::Symlink < ::MItamae::ResourceExecutor::Base
  def apply
    case desired.action
    when :create
      create!
    when :delete
      delete!
    when :nothing
      # do nothing
    end
  end

  private

  def set_current_attributes(current, desired)
  end

  def set_desired_attributes(desired, action)
  end

  def create!
    MItamae.logger.info "#{@resource.resource_type}[#{desired.path}] created will change from 'false' to 'true'"
    File.unlink(desired.path) if desired.force && File.exist?(desired.path)
    File.symlink(desired.source, desired.path)
  end

  def delete!
    MItamae.logger.info "#{@resource.resource_type}[#{desired.path}] created will change from 'true' to 'false'"
    File.unlink(desired.path)
  end
end
