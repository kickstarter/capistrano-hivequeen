# HTTP Client for Hive Queen environment configuration
require 'base64'
require 'fileutils'
require 'json'

require 'active_support'
require 'active_support/core_ext'
require 'aws-sdk-ec2'
require 'aws-sdk-ec2instanceconnect'
require 'excon'

require 'capistrano/hivequeen/version'
require 'capistrano/hivequeen/multiio'
require 'capistrano/hivequeen/ec2_instance_connect'

# Special cases:
# - environment not found
# - environment not ready: fail
class HiveQueen
  class DeploymentError < Exception; end
  class InsecureCredentials < Exception; end

  class << self
    attr_accessor :endpoint, :logger, :project, :username, :password

    def project_data
      @project_data ||= get("/#{project}.json")
    end

    def default_roles
      @project_data['default_roles']
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
      @roles[env_id] ||= get("/#{env_id}.json")
    end

    def commit_status(commit_sha)
      get("/projects/#{project}/commit_statuses/#{commit_sha}.json")
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
      deploy_log = logger.device.history
      params[:deployment][:deploy_log] = deploy_log if deploy_log
      put_or_post('PUT', "/environments/#{environment_id}/deployments/#{deployment_id}.json", params)
    end

    # Load credentials from ~/.hivequeen
    def get_credentials!
      creds = ENV['HIVEQUEEN_CREDENTIALS'] || credentials_from_path
      @username, @password = creds.chomp.split(':')
      raise unless username && password
    end

    def credentials_from_path
      # Check that credentials are not accessible to world or group
      mode = File.stat(credentials_path).mode
      raise InsecureCredentials unless (mode % 64 == 0)

      File.read(credentials_path)

    rescue InsecureCredentials
      puts "#{credentials_path} is insecure. Please change you password and run"
      puts "chmod 600 #{credentials_path}"
      exit 1
    rescue Errno::ENOENT, RuntimeError
      puts "Could not read HiveQueen credentials from #{credentials_path}."
      puts "#{credentials_path} should contain your username and password seperated by a colon"
      puts "Run this command with your credentials:"
      puts " $ echo username:password > #{credentials_path}; chmod 600 #{credentials_path}"
      exit 1
    end

    protected
    def credentials_path
      ENV['HIVEQUEEN_CREDENTIALS_PATH'] || File.join(ENV['HOME'], '.hivequeen')
    end

    def connection
      Excon.new(endpoint)
    end

    def auth_header
      value = Base64.encode64([username, password] * ':').gsub(/\n/, '')
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

require "capistrano/hivequeen/capistrano_configuration"
