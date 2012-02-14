# Load environment configuration from HiveQueen
require "capistrano/hivequeen/server"

Capistrano::Configuration.instance(:must_exist).load do
  HiveQueen.endpoint = hivequeen_endpoint
  HiveQueen.project = application
  HiveQueen.logger = logger
  HiveQueen.get_credentials!

  # Redefine stage tasks from multistage extension
  # Set the list of available stages
  set :stages, HiveQueen.environment_names

  # Default to using the current branch as the stage name
  # NB: current branch may not be set
  current_branch = `git symbolic-ref HEAD`.chomp.sub('refs/heads/', '')
  unless current_branch.empty?
    env_name = HiveQueen.environment_for_branch(current_branch)
    set(:default_stage, env_name) if env_name
  end

  set :repository, HiveQueen.repository
  set :scm, :git
  ssh_options[:forward_agent] = true

  # By default, don't override deployments if there's another deployment in progress.
  # From the command line, use -s override=true to force a deployment
  set :override, false

  # Time to wait for Background jobs processes to start/stop
  set :bg_wait_time, 30

  # Load capistrano multi-stage extension
  require 'fileutils' # required until https://github.com/capistrano/capistrano-ext/commit/930ca840a0b4adad0ec53546790b3f5ffe726538 is released
  require 'capistrano/ext/multistage'
  require 'capistrano/hivequeen/setup'
  require 'capistrano/hivequeen/deploy'

  # Redefine stage tasks from multistage extension
  HiveQueen.environments.each do |env|
    name = env['name']
    hive_queen_id = env['id']

    desc "Use environment #{name}"
    task name do
      environment = HiveQueen.roles(hive_queen_id)
      # Check if environment is ready
      unless environment['state'] == 'running'
        abort "Environment #{name} is not ready. State: #{environment['state']}"
      end

      set :stage, name.to_sym
      set :rails_env, name
      set :environment_id, hive_queen_id
      unless exists?(:branch)
        set :branch, environment['branch']
      end

      # Set servers for each role
      environment['roles'].each do |role_name, role_config|
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
end
