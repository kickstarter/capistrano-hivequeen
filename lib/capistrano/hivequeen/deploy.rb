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
    before 'hivequeen:start', 'hivequeen:check_commit'
  on :start, "hivequeen:require_environment", :except => HiveQueen.environment_names
  namespace :hivequeen do

    desc "[internal] abort if no environment specified"
    task :require_environment do
      abort "No environment specified." if !exists?(:environment)
    end

    desc "[internal] Start a deployment in hivequeen"
    task :start do
      # TODO: is there a better way to determine what cap tasks are running?
      tasks = ARGV.reject{|task_name| environment.to_s == task_name}

      params = {
        :task => tasks.join(' '),
        :commit => real_revision,
        :override => override
      }

      if current_commit
        params[:change_log] = changelog_command
        if params[:change_log].size > changelog_maxbytes
          params[:change_log] = params[:change_log][0..changelog_maxbytes - 1]
          logger.debug "Change log too large, truncating"
        end
      end

      begin
        deployment = HiveQueen.start_deployment(environment_id, params)
        set :deployment_id, deployment['id']
        at_exit { HiveQueen.finish_deployment(environment_id, deployment['id']) }
      rescue HiveQueen::DeploymentError
        abort "Cannot start deployment. Errors: #{$!.message}"
      end
    end

    desc "[internal] Prompt if deploying the currently running commit, or if tests haven't passed"
    task :check_commit do
      if environment.to_s == 'production'
        if current_commit == real_revision
          banner = %q{
 ______                   _     _                          _    ___
|  ____|                 | |   | |                        | |  |__ \
| |__ ___  _ __ __ _  ___| |_  | |_ ___    _ __  _   _ ___| |__   ) |
|  __/ _ \| '__/ _` |/ _ \ __| | __/ _ \  | '_ \| | | / __| '_ \ / /
| | | (_) | | | (_| |  __/ |_  | || (_) | | |_) | |_| \__ \ | | |_|
|_|  \___/|_|  \__, |\___|\__|  \__\___/  | .__/ \__,_|___/_| |_(_)
                __/ |                     | |
               |___/                      |_|
}
          puts banner
          puts "\n\nCommit #{current_commit} is currently deployed\n"
          Capistrano::CLI.ui.ask("Did you forget to push a new commit? Press enter to continue deploying, or ctrl+c to abort")
        end

        banner = %q{
 _______        _             _ _     _       _ _                         _
|__   __|      | |           | (_)   | |     ( ) |                       | |
   | | ___  ___| |_ ___    __| |_  __| |_ __ |/| |_   _ __   __ _ ___ ___| |
   | |/ _ \/ __| __/ __|  / _` | |/ _` | '_ \  | __| | '_ \ / _` / __/ __| |
   | |  __/\__ \ |_\__ \ | (_| | | (_| | | | | | |_  | |_) | (_| \__ \__ \_|
   |_|\___||___/\__|___/  \__,_|_|\__,_|_| |_|  \__| | .__/ \__,_|___/___(_)
                                                     | |
                                                     |_|
}
        puts "Checking commit status for #{real_revision}"
        status = HiveQueen.commit_status(real_revision)
        unless status && status['state'] == "success"
          puts banner

          message = "Commit status is %s." % (status['state'] || 'unknown')
          if status['target_url']
            message << " See #{status['target_url']}"
          end
          puts "\n\n#{message}\n"

          Capistrano::CLI.ui.ask("Are you sure you want to deploy when tests haven't passed? Press enter to continue deploying, or ctrl+c to abort")
        end
      end
    end
  end

  # Keep all but the 5 most recent releases
  set :keep_releases, 5
  after "deploy", "deploy:cleanup"

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
  before "deploy:create_symlink", "bg:stop"
  # Restart background jobs after the app is restarted
  after "deploy:restart", "bg:restart"

  namespace :bg do
    %w(start stop restart).each do |action|
      desc "#{action} the delayed_job processes"
      task action, :roles => fetch(:bg_roles, [:bg]) do
        begin
          run "sv #{action} `cd /etc/service; ls -d dj_*`"
        rescue Capistrano::CommandError
          if tolerate_slow_bg
            logger.info "Some bg workers did not #{action} quickly, but will #{action} when the current job finishes."
            logger.info "Consider running with '-s tolerate_slow_bg=false'"
          else
            raise $!
          end
        end
      end

    end
  end
end
