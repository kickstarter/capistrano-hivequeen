Capistrano::Configuration.instance(:must_exist).load do
  # Capture capistrano log output
  @logger = Capistrano::Logger.new(:output => HiveQueen::MultiIO.new)
  @logger.level = Capistrano::Logger::DEBUG

  HiveQueen.endpoint = hivequeen_endpoint
  HiveQueen.project = application
  HiveQueen.logger = logger
  HiveQueen.get_credentials!

  # Require bundler extensions
  require 'bundler/capistrano'

  # Default to using the current branch as the stage name
  # NB: current branch may not be set
  #current_branch = `git symbolic-ref HEAD`.chomp.sub('refs/heads/', '')

  set :repository, HiveQueen.repository
  set :scm, :git
  ssh_options[:forward_agent] = true
  set :deploy_via, :remote_cache

  # By default, don't override deployments if there's another deployment in progress.
  # From the command line, use -s override=true to force a deployment
  set :override, false

  # If a delayed_job worker doesn't stop/restart in time (probably b/c a slow job is running)
  # trust that runit will eventually stop/restart the worker
  set :tolerate_slow_bg, true

  # Option to skip background tasks
  set :skip_bg, false

  # Command to get the changes being deployed
  set :changelog_command do
    `git log #{current_commit}...#{real_revision} --pretty="%n%h %an: %s (%ar)" --stat --no-color`
  end

  # Limit of change log size
  set :changelog_maxbytes, 700 * 1024

  # Don't mess with timestamps
  set :normalize_asset_timestamps, false
  # Don't mess with permissions
  set :group_writable, false
  set :use_sudo, false

  # Define environment tasks
  HiveQueen.environments.each do |env|
    name = env['name']
    hive_queen_id = env['id']
    current_commit = env['current_commit']

    desc "Use environment #{name}"
    task name do
      env = HiveQueen.roles(hive_queen_id)
      # Check if environment is ready
      unless env['state'] == 'running'
        abort "Environment #{name} is not ready. State: #{env['state']}"
      end

      set :environment, name.to_sym
      set :rails_env, name
      set :environment_id, hive_queen_id
      set :current_commit, current_commit
      unless exists?(:branch)
        set :branch, env['branch']
      end

      # Set servers for each role
      env['roles'].each do |role_name, role_config|
        role(role_name.to_sym) { role_config['servers'] }
      end

      # Ensure some server designated as db server
      unless roles.key?(:db)
        # Prefer the bg server
        db_server = roles[:bg].servers.first if roles.key?(:bg)

        # Otherwise, use any server
        db_server ||= roles.values.map{|x| x.servers}.flatten.compact.first
        logger.trace "Using #{db_server} as primary db server"
        role :db, db_server.to_s, :primary => true
      end

    end
  end

  namespace :ssh do
    HiveQueen.default_roles.each do |role_name|
      task role_name do
        cmd =  "ssh -t -A -l #{user} #{roles[role_name.to_sym].servers.first}"
        puts "Executing #{cmd}"
        exec cmd
      end
    end

  end

  require 'capistrano/hivequeen/setup'
  require 'capistrano/hivequeen/deploy'


end
