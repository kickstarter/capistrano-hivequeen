Capistrano::Configuration.instance.load do
  # Symlink shared config files
  after "deploy:update_code", "deploy:symlink_shared_config"
  namespace :deploy do
    desc "[internal] Symlink shared config files to current release"
    task :symlink_shared_config do
      run "ln -nfs #{shared_path}/config/* #{latest_release}/config"
    end
  end

  before "deploy:update_code", "hivequeen:start"
  before "setup",         "hivequeen:start"
  namespace :hivequeen do
    desc "[internal] Start a deployment in hivequeen"
    task :start do
      # TODO: is there a better way to determine what cap tasks are running?
      tasks = ARGV.reject{|task_name| stage.to_s == task_name}
      params = {
        :task => tasks.join(' '),
        :commit => real_revision,
        :override => override
      }
      begin
        deployment = HiveQueen.start_deployment(environment_id, params)
        set :deployment_id, deployment['id']
        at_exit { HiveQueen.finish_deployment(environment_id, deployment['id']) }
      rescue HiveQueen::DeploymentError
        abort "Cannot start deployment. Errors: #{$!.message}"
      end
    end
  end

  desc "Deploy without migrations"
  task(:hotfix) { deploy.default }

  namespace :deploy do
    desc "[internal] Original Capistrano task. Don't run this."
    task :cold do
      # Nothing. Use :cold task below
    end
  end

  desc "Deploy for the first time. Runs setup and deploy:migrations"
  task :cold do
    setup
    deploy.migrations
  end

  desc "Show servers & roles"
  task :show do
    roles.each do |name, value|
      servers = value.servers
      logger.debug "== #{name} role (#{servers.size} servers):"
      logger.debug servers.join("\n") if servers.any?
    end
  end

  before "deploy:restart", "app:upgrade"
  namespace :app do
    # NB: if preload_app is true, reload will not pick up application changes.
    # Use upgrade instead.
    # See http://unicorn.bogomips.org/SIGNALS.html
    %w(start stop restart upgrade).each do |action|
      desc "#{action} the unicorn processes"
      task action, :roles => fetch(:app_roles, [:app]) do
        run "/etc/init.d/unicorn_#{application} #{action}"
      end
    end
  end

  # Ensure background jobs are stopped before running a migrations
  before "deploy:migrate", "bg:stop"
  # Ensure background jobs are stopped before symlinking (as part of a normal deploy)
  before "deploy:symlink", "bg:stop"
  # Restart background jobs after the app is restarted
  after "deploy:restart", "bg:restart"

  namespace :bg do
    %w(start stop restart).each do |action|
      desc "#{action} the delayed_job processes"
      task action, :roles => fetch(:bg_roles, [:bg]) do
        run "sv -w #{bg_wait_time } #{action} `cd /etc/service; ls -d dj_*`"
      end
    end
  end

end
