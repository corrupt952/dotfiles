require_relative "../test_helper"

load "#{git_root_path}/.config/git/hooks/pre-push"

describe 'Git pre-push hook' do
  describe '#main_branch?' do
    context 'branch_name is main' do
      it 'be true' do
        assert main_branch? 'main'
      end
    end

    context 'branch_name is master' do
      it 'be true' do
        assert main_branch? 'master'
      end
    end

    context 'branch_name is develop' do
      it 'be false' do
        assert ! main_branch?('develop')
      end
    end
  end

  describe '#restrict_branches' do
    context 'branch_name is main' do
      it 'be fail' do
        assert_raises RuntimeError do
          restrict_branches 'main'
        end
      end
    end

    context 'branch_name is develop' do
      it 'be nothing' do
        restrict_branches 'develop'
      end
    end

    context 'branch_name is main && GIT_ALLOW_PUSH_MAIN_BRANCH=yes' do
      it 'be nothing' do
        current = ENV['GIT_ALLOW_PUSH_MAIN_BRANCH']
        ENV['GIT_ALLOW_PUSH_MAIN_BRANCH'] = 'yes'

        restrict_branches 'main'

        ENV['GIT_ALLOW_PUSH_MAIN_BRANCH'] = current
      end
    end
  end

  describe '#use_force_option?' do
    context '--force in command' do
      it 'be true' do
        assert use_force_option? 'git push --force origin main'
      end
    end

    context '-f in command' do
      it 'be true' do
        assert use_force_option? 'git push --force origin main'
      end
    end

    context 'not force push command' do
      it 'be false' do
        assert ! use_force_option?('git push origin master')
      end
    end
  end

  describe '#restrict_force_push' do
    context '--force-with-lease in command' do
      it 'be nothing' do
        assert_raises RuntimeError do
          restrict_force_push 'git push --force-with-lease origin master'
        end
      end
    end

    context '-f in command && GIT_ALLOW_FORCE_PUSH=yes' do
      it 'be nothing' do
        current = ENV['GIT_ALLOW_FORCE_PUSH']
        ENV['GIT_ALLOW_FORCE_PUSH'] = 'yes'

        restrict_force_push 'git push -f origin master'

        ENV['GIT_ALLOW_FORCE_PUSH'] = current
      end
    end

    context 'not force push command' do
      it 'be nothing' do
        restrict_force_push 'git push origin master'
      end
    end
  end
end
