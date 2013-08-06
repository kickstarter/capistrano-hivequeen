Capistrano::Configuration.instance(:must_exist).load do
  # Require bundler extensions
  require 'bundler/capistrano'

  # Default to using the current branch as the stage name
  # NB: current branch may not be set
  #current_branch = `git symbolic-ref HEAD`.chomp.sub('refs/heads/', '')

  set :scm, :git
  set :deploy_via, :remote_cache

  # If a delayed_job worker doesn't stop/restart in time (probably b/c a slow job is running)
  # trust that runit will eventually stop/restart the worker
  set :tolerate_slow_bg, true

  # Option to skip background tasks
  set :skip_bg, false

  # Don't mess with timestamps
  set :normalize_asset_timestamps, false
  # Don't mess with permissions
  set :group_writable, false
  set :use_sudo, false

  # Symlink shared config files
  after "deploy:update_code", "deploy:symlink_shared_config"
  namespace :deploy do
    desc "[internal] Symlink shared config files to current release"
    task :symlink_shared_config do
      run "ln -nfs #{shared_path}/config/* #{latest_release}/config"
    end
  end

  before "deploy:update_code", "hivequeen:start"

  # Keep all but the 5 most recent releases
  set :keep_releases, 5
  after "deploy", "deploy:cleanup"

  after "deploy:restart", "deploy:restart_rails_services"
  namespace :deploy do
    desc "restarts all rails services concurrently"
    task :restart_rails_services, :roles => [:app, :bg, :resque] do
      run "/etc/init.d/rails_services upgrade"
    end
  end

end
