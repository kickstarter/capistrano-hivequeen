# HTTP Client for Hive Queen environment configuration
require 'open-uri'
require 'json'
require 'fileutils'

# Special cases:
# - environment not found
# - environment not ready: fail
class HiveQueen
  class << self
    attr_accessor :endpoint, :logger

    def project_data
      @project_data ||= fetch('/projects/kickstarter')
    end

    def environments
      project_data['environments']
    end

    def environment_names
      environments.map{|e| e['name'].to_sym }
    end

    def repository
      project_data['repo']
    end

    def roles(env_id)
      env_id = env_id.to_sym
      @roles ||= {}
      @roles[env_id] ||= fetch("/environments/#{env_id}")
    end

    protected
    def fetch(path)
      url = endpoint + path + '.json'
      logger.trace "Fetching #{url}"
      JSON.parse(open(url).read)
    end

  end
end
