# Don't load this if legacy_deploy is loaded
# Can be moved into capistrano/hivequeen/deploy.rb
# after legacy stuff is removed
Capistrano::Configuration.instance.load do
  namespace :deploy do
    desc "restarts all rails services concurrently"
    task :restart, :roles => deploy_roles do
      run "/etc/init.d/rails_services upgrade"
    end
  end
end
