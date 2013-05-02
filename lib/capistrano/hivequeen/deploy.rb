Capistrano::Configuration.instance.load do
  # Redefine the basic deploy tasks were need for
  # S3 tarballs
  namespace :deploy do
    desc "Deploy"
    task :default do
      deploy.stage
      deploy.release
    end

    desc "Prepares for release by bundling gems, symlinking shared files, etc"
    task :stage do
      deploy.extract
      deploy.config
      run "cd #{release_path} && deploy/remote/stage"
    end

    desc "Runs the release script to symlink a staged deploy and restarts services"
    task :release do
      run "cd #{release_path} && deploy/remote/release"
    end

    desc "Downloads and extracts a tarball on S3 to the remote servers"
    task :extract do
      deploy.upload
      # Needs url, real_revision, deploy_to, current_path
      # NB: pipe stderr to /dev/null to avoid a bunch of messages about
      # "Ignoring unknown extended header keyword" due to
      # incompatibilities with bsdtar (os x) and gnutar (linux). Yay!
      run "mkdir -p #{release_path} && curl -s '#{s3_tarball.download_url}' | tar -zxC #{release_path} 2> /dev/null"
    end

    desc "Uploads deploy config file"
    task :config do
      deploy_config_data = %{
RELEASE_PATH=#{release_path}
RELEASES_PATH=#{File.dirname(release_path)}
CURRENT_PATH=#{current_path}
KEEP_RELEASES=#{keep_releases}
SHARED_PATH=#{shared_path}
RAILS_ENV=#{rails_env}
}
      put(deploy_config_data, deploy_config)
    end

    desc "Checks that a deployable tarball is on S3; creates it if missing"
    task :upload do
      `deploy/upload`
      abort "Failed to upload build" if $?.exitstatus != 0
    end
  end

  before "deploy:extract", "hivequeen:start"
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

  after "deploy:restart", "deploy:restart_rails_services"
  namespace :deploy do
    desc "restarts all rails services concurrently"
    task :restart_rails_services, :roles => [:app, :search, :bg, :resque] do
      run "/etc/init.d/rails_services restart"
    end
  end
end
