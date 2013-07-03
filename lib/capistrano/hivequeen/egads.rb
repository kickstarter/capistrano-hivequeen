# Don't load this if legacy_deploy is loaded
# Can be moved into capistrano/hivequeen/deploy.rb
# after legacy stuff is removed
Capistrano::Configuration.instance.load do
  namespace :deploy do
    desc "restarts all rails services concurrently"
    task :restart do
      run "if [ -x /etc/init.d/rails_services ]; then /etc/init.d/rails_services upgrade; fi"
    end
  end
end
