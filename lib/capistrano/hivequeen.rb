# Load environment configuration from HiveQueen
require "capistrano/hivequeen/server"

Capistrano::Configuration.instance(:must_exist).load do
  HiveQueen.endpoint = hivequeen_endpoint
  HiveQueen.project = application
  HiveQueen.logger = logger

  # Redefine stage tasks from multistage extension
  # Set the list of available stages
  set :stages, HiveQueen.environment_names
  # When no stage is specified, use staging
  set :default_stage, :staging

  set :repository, HiveQueen.repository

  # Load capistrano multi-stage extension
  require 'fileutils' # required until https://github.com/capistrano/capistrano-ext/commit/930ca840a0b4adad0ec53546790b3f5ffe726538 is released
  require 'capistrano/ext/multistage'

  # Redefine stage tasks from multistage extension
  HiveQueen.environments.each do |env|
    name = env['name']
    hive_queen_id = env['id']

    desc "Use environment #{name}"
    task name do
      set :stage, name.to_sym
      set :environment_id, env['id']
      environment = HiveQueen.roles(hive_queen_id)
      # Check if environment is ready
      unless environment['state'] == 'running'
        abort "Environment #{name} is not ready. State: #{environment['state']}"
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
