Capistrano::Configuration.instance(:must_exist).load do
  # Capture capistrano log output
  @logger = Capistrano::Logger.new(:output => HiveQueen::MultiIO.new)
  @logger.level = Capistrano::Logger::TRACE

  HiveQueen.endpoint = hivequeen_endpoint
  HiveQueen.project = application
  HiveQueen.logger = logger
  HiveQueen.get_credentials!

  set :repository, HiveQueen.repository
  ssh_options[:forward_agent] = true

  # By default, don't override deployments if there's another deployment in progress.
  # From the command line, use -s override=true to force a deployment
  set :override, false

  # Don't mark deployments as canary deployments by default
  set :canary, false

  # Command to get the changes being deployed
  set :changelog_command do
    `git log #{current_commit}...#{real_revision} --pretty="%n%h %an: %s (%ar)" --stat --no-color`
  end

  # Default to using `git ls-remote` to resolve SHA from github.
  # Run with `-s github=false` to remove dependency on remote.
  set :github, true

  # Parse sha from branch; depends on remote git repo.
  set :sha do
    raise "Must specify a branch" unless branch.present?
    if github
      line = `git ls-remote #{repository} #{branch}`.split("\n").first
      raise "Unable to find sha for branch #{branch}" unless line.presence.try {|l| l.split.last == "refs/heads/#{branch}"}
      line.split.first
    else
      warn "Skipping github, using local git checkout"
      branch
    end
  end

  # Expand sha into a complete git sha
  set :full_sha do
    full_sha = `git rev-parse --verify #{sha}`.strip
    raise "#{sha} is not a valid git ref. Run `git fetch` and try again?" if sha.to_s.empty?
    full_sha
  end

  # Limit of change log size
  set :changelog_maxbytes, 700 * 1024

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
        servers = role_config['instances']
        if exists?(:az)
          servers = servers.select {|s| s['availability_zone'] == az}
        end
        role(role_name.to_sym) { servers.map {|s| s['public_dns'] || s['private_dns']} }
      end

      # Ensure some server designated as db server
      unless roles.key?(:db)
        # Prefer a background worker role
        bg = (roles.keys & [:bg, :resque, :sidekiq]).sample
        db_server = roles[bg].servers.sample if roles.key?(bg)

        # Otherwise, use any server
        db_server ||= roles.values.map{|x| x.servers}.flatten.compact.sample
        logger.trace "Using #{db_server} as primary db server"
        role :db, db_server.to_s, :primary => true
      end

      namespace :ssh do
        command_format = "ssh -t -A -l %s %s"
        env['roles'].keys.each do |role_name|
          task role_name do
            server = roles[role_name.to_sym].servers.sample
            HiveQueen.ec2_instance_connect(server.host)
            cmd = command_format % [user, server]
            puts "Executing #{cmd}"
            exec cmd
          end
        end

        task :default do
          server = roles.values.sample.servers.sample
          HiveQueen.ec2_instance_connect(server.host)
          cmd = command_format % [user, server]
          puts "Executing #{cmd}"
          exec cmd
        end
      end

      namespace :console do
        command_format = "ssh -t -A -l %s %s 'source /etc/profile; cd /apps/#{HiveQueen.project}/current && bundle exec rails console'"
        env['roles'].keys.each do |role_name|
          task role_name do
            server = roles[role_name.to_sym].servers.sample
            HiveQueen.ec2_instance_connect(server.host)
            puts "Opening console"
            exec command_format % [user, server]
          end
        end

        task :default do
          server = roles.values.sample.servers.sample
          HiveQueen.ec2_instance_connect(server.host)
          puts "Opening console"
          exec command_format % [user, server]
        end
      end
    end
  end

  require 'capistrano/hivequeen/setup'
  require 'capistrano/hivequeen/deploy'

end
