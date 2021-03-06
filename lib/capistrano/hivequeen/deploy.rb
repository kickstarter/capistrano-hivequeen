Capistrano::Configuration.instance.load do

  # Redefine real_revision
  # real_revision is a legacy name from the default capistrano recipes
  set(:real_revision) { full_sha }

  before "deploy:stage", "hivequeen:start"
  before 'hivequeen:start', 'hivequeen:check_commit'
  on :start, "hivequeen:require_environment", :except => HiveQueen.environment_names
  on :start, "hivequeen:ensure_canary_specifies_hosts"

  namespace :hivequeen do

    desc "[internal] abort if no environment specified"
    task :require_environment do
      abort "No environment specified." if !exists?(:environment)
    end

    desc "[internal] abort if we're trying to do a canary deploy but HOSTS hasn't been defined"
    task :ensure_canary_specifies_hosts do
      # TODO: I suppose we could randomly select instance(s) in this case
      if canary && !ENV.key?('HOSTS')
        abort "You asked to do a canary deployment but didn't specify any hosts! \nPlease invoke like `cap HOSTS=foo.com deploy -s canary=true'"
      end
    end

    desc "[internal] Start a deployment in hivequeen"
    task :start do
      # TODO: is there a better way to determine what cap tasks are running?
      tasks = ARGV.reject{|task_name| environment.to_s == task_name}

      params = {
        :task => tasks.join(' '),
        :commit => real_revision,
        :override => override,
        :canary => canary,
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
      if environment.to_s == 'production' && !override && !canary
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

        tests_didnt_pass = %q{
 _______        _             _ _     _       _ _                         _
|__   __|      | |           | (_)   | |     ( ) |                       | |
   | | ___  ___| |_ ___    __| |_  __| |_ __ |/| |_   _ __   __ _ ___ ___| |
   | |/ _ \/ __| __/ __|  / _` | |/ _` | '_ \  | __| | '_ \ / _` / __/ __| |
   | |  __/\__ \ |_\__ \ | (_| | | (_| | | | | | |_  | |_) | (_| \__ \__ \_|
   |_|\___||___/\__|___/  \__,_|_|\__,_|_| |_|  \__| | .__/ \__,_|___/___(_)
                                                     | |
                                                     |_|
}
        tests_running = %q{

 _______        _                                _
|__   __|      | |                              (_)
   | | ___  ___| |_ ___   _ __ _   _ _ __  _ __  _ _ __   __ _
   | |/ _ \/ __| __/ __| | '__| | | | '_ \| '_ \| | '_ \ / _` |
   | |  __/\__ \ |_\__ \ | |  | |_| | | | | | | | | | | | (_| |_ _ _
   |_|\___||___/\__|___/ |_|   \__,_|_| |_|_| |_|_|_| |_|\__, (_|_|_)
                                                          __/ |
                                                         |___/

}
        puts "Checking commit status for #{real_revision}"
        status = HiveQueen.commit_status(real_revision)
        unless status && status['state'] == "success"
          banner = status['state'] == 'pending' ? tests_running : tests_didnt_pass
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

  desc "Deploy without migrations"
  task(:hotfix) { deploy.default }

  namespace :deploy do
    desc "[internal] Original Capistrano task. Don't run this."
    task :cold do
      # Nothing. Use :cold task below
    end

    desc "restarts all rails services concurrently"
    task :restart, max_hosts: 3 do
      restart_cmd = "if [ -x /etc/init.d/rails_services ]; then /etc/init.d/rails_services upgrade; fi"
      # Restart non-app servers all-at-once
      run restart_cmd, roles: (roles.keys - [:app])
      # Restart app servers in batchs of 3
      run restart_cmd, max_hosts: 10, roles: :app
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

end
