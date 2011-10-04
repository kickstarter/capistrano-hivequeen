# HTTP Client for Hive Queen environment configuration
require 'json'
require 'fileutils'
require 'excon'
require 'base64'

# Special cases:
# - environment not found
# - environment not ready: fail
class HiveQueen
  class << self
    attr_accessor :endpoint, :logger, :project, :username, :password

    def project_data
      @project_data ||= fetch("/projects/#{project}.json")
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
      @roles[env_id] ||= fetch("/environments/#{env_id}.json")
    end

    # Try to load credentials, or read them from ~/.hivequeen
    def set_credentials!
      @username, @password = File.read(credential_path).chomp.split(':')
      raise unless username && password
    rescue Errno::ENOENT, RuntimeError
      puts "Could not read HiveQueen credentials from #{credential_path}."
      puts "#{credential_path} should contain your username and password seperated by a colon"
      puts "Run this command with your credentials:"
      puts " $ echo username:password > #{credential_path}"
      exit 1
    end

    protected
    def credential_path
      File.join(ENV['HOME'], '.hivequeen')
    end

    def connection
      @connection ||= Excon.new(endpoint)
    end

    def auth_header
      value = Base64.encode64([username, password] * ':').chomp
      { 'Authorization' => "Basic #{value}" }
    end

    def fetch(path)
      logger.trace "Fetching #{endpoint}/#{path}"
      response = connection.get(:path => path, :headers => auth_header)
      unless (200..299).include?(response.status)
        raise "Request to #{endpoint}/#{path} returned #{response.status} status"
      end
      JSON.parse(response.body)
    end

  end
end
