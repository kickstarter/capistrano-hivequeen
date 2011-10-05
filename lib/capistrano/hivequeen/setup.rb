# Capistrano tasks for Chef

Capistrano::Configuration.instance.load do

  # Resets the user for a block
  # Based on http://www.pgrs.net/2008/08/06/switching-users-during-a-capistrano-deploy/
  def as_user(new_user=nil)
    logger.trace "Using the current user account"
    old_user = user
    set :user, new_user
    close_sessions
    yield
    set :user, old_user
    close_sessions
  end

  def close_sessions
    sessions.values.each { |session| session.close }
    sessions.clear
  end

  namespace :deploy do
    desc "[internal] Original Capistrano task. Don't run this."
    task(:setup) do
      # Nothing, run setup task below
    end
  end

  desc "Run chef-client on all servers"
  task :setup do
    as_user do
      sudo "chef-client"
    end
  end
end
