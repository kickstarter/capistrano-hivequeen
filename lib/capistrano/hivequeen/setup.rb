# Capistrano tasks for Chef

Capistrano::Configuration.instance.load do
  namespace :deploy do
    desc "[internal] Original Capistrano task. Don't run this."
    task(:setup) do
      # Nothing, run setup task below
    end
  end

  desc "Run chef-client on all servers"
  task :setup do
    logger.trace "Using the current user account"
    orig_user = user
    set :user, nil # Use current user account
    sudo "chef-client"

    # Reset user
    logger.trace "Resetting user to #{orig_user}"
    set :user, orig_user
  end
end
