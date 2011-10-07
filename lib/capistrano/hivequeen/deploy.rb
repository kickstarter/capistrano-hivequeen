Capistrano::Configuration.instance.load do
  # Symlink shared config files
  after "deploy:update_code", "deploy:symlink_shared_config"
  namespace :deploy do
    desc "[internal] Symlink shared config files to current release"
    task :symlink_shared_config do
      run "ln -nfs #{shared_path}/config/* #{latest_release}/config"
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
end
