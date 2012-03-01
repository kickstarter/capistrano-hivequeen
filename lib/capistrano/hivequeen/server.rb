# HTTP Client for Hive Queen environment configuration
require 'json'
require 'fileutils'
require 'excon'
require 'base64'

# Special cases:
# - environment not found
# - environment not ready: fail
class HiveQueen
  class DeploymentError < Exception; end
  class InsecureCredentials < Exception; end

  class << self
    attr_accessor :endpoint, :logger, :project, :username, :password

    def project_data
      @project_data ||= get("/projects/#{project}.json")
    end

    def environments
      project_data['environments']
    end

    def environment_names
      environments.map{|e| e['name'].to_sym }
    end

    def environment_for_branch(branch)
      env = environments.detect{|e| e['branch'] == branch }
      env['name'] if env
    end

    def repository
      project_data['repo']
    end

    def roles(env_id)
      env_id = env_id.to_sym
      @roles ||= {}
      @roles[env_id] ||= get("/environments/#{env_id}.json")
    end

    def start_deployment(environment_id, params)
      required_params = [:task, :commit]
      required_params.each do |key|
        raise ArgumentError.new("#{key} is a required param") unless params.key?(key)
      end
      put_or_post('POST', "/environments/#{environment_id}/deployments.json", :deployment => params)
    end

    def finish_deployment(environment_id, deployment_id)
      state = $! ? 'failed' : 'succeeded'
      puts "Finishing deployment in Hivequeen. State: #{state}"
      params = {:deployment => {:state => state}}
      put_or_post('PUT', "/environments/#{environment_id}/deployments/#{deployment_id}.json", params)
    end

    # Load credentials from ~/.hivequeen
    def get_credentials!
      @username, @password = File.read(credential_path).chomp.split(':')
      raise unless username && password
      # Check that credentials are not accessible to world or group
      mode = File.stat(credential_path).mode
      raise InsecureCredentials unless (mode % 64 == 0)
    rescue InsecureCredentials
      puts "#{credential_path} is insecure. Please change you password and run"
      puts "chmod 600 #{credential_path}"
      exit 1
    rescue Errno::ENOENT, RuntimeError
      puts "Could not read HiveQueen credentials from #{credential_path}."
      puts "#{credential_path} should contain your username and password seperated by a colon"
      puts "Run this command with your credentials:"
      puts " $ echo username:password > #{credential_path}; chmod 600 #{credential_path}"
      exit 1
    end

    protected
    def credential_path
      File.join(ENV['HOME'], '.hivequeen')
    end

    def connection
      Excon.new(endpoint)
    end

    def auth_header
      value = Base64.encode64([username, password] * ':').chomp
      { 'Authorization' => "Basic #{value}" }
    end

    def get(path)
      url = "#{endpoint}#{path}"
      logger.trace "Fetching #{url}"
      response = connection.request(:method => 'GET', :path => path, :headers => auth_header)
      unless (200..299).include?(response.status)
        raise "Request to #{url} returned #{response.status} status"
      end
      JSON.parse(response.body)
    end

    def put_or_post(method, path, data)
      headers = auth_header.merge("Content-type"=>"application/json", "Accept"=>"application/json")
      response = connection.request(:path => path, :method => method, :headers => headers, :body => data.to_json)
      case response.status
      when 204
        # Do nothing
      when (200..299)
        JSON.parse(response.body)
      when (400..499)
        errors = JSON.parse(response.body)
        raise DeploymentError.new(errors.inspect)
      else
        raise "Request to #{path} returned #{response.status} status"
      end
    end

  end
end
