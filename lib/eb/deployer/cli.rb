require 'eb/deployer'
require 'thor'
require 'aws-sdk-core'

module Eb::Deployer
  class CLI < Thor
    class_option :aws_credential_file
    class_option :access_key_id
    class_option :secret_access_key
    class_option :application_config
    class_option :application_name
    class_option :region


    desc 'get_cname target_environment', 'Get a cname by target environment name'
    def get_cname(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      if ret[:environments].length == 1
        puts ret[:environments][0].cname
      else
        puts ''
      end
    end

    desc 'check_exist target_environment', 'Get true if exist target environment name'
    def check_exist(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      if ret[:environments].length == 1
        puts true
      else
        puts false
      end
    end

    option :template_name
    option :tier
    option :cname
    option :option_settings_file
    desc 'start environment_name', 'Start an environment'
    def start(environment_name)
      params = {
        application_name: application_name,
        environment_name: environment_name,
        cname_prefix: cname ? cname : environment_name
      }
      params.store(:tier, tier) if tier
      params.store(:template_name, template_name) if template_name
      params.store(:option_settings, option_settings) if option_settings
      ret = client.create_environment(params)
      puts ret[:environment_id]
    end

    desc 'status environment_name', 'Get status by target environment name'
    def status(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      puts ret[:environments][0].to_hash.to_json
    end

    private

    def access_key_id
      fetch_attribute(:access_key_id)
    end

    def secret_access_key
      fetch_attribute(:secret_access_key)
    end

    def region
      fetch_attribute(:region)
    end

    def application_name
      fetch_attribute(:application_name)
    end

    def template_name
      fetch_attribute(:template_name, false)
    end

    def cname
      fetch_attribute(:cname, false)
    end

    def option_settings
      option_file = fetch_attribute(:option_settings_file, false)
      return nil unless option_file
      if File.exist?(option_file)
        return(eval(File.read(option_file)))
      else
        raise Exception.new "#{option_file} is not found."
      end
    end

    def tier
      tier_value = fetch_attribute(:tier, false)
      if tier_value == 'worker'
        return {
          name: 'Worker',
          type: 'Standard',
          version: '1.1'
        }
      elsif tier_value == 'webserver'
        return {
          name: 'WebServer',
          type: 'Standard',
          version: '1.0'
        }
      end
      nil
    end

    def fetch_attribute(symbol, raise_error = true)
      return options[symbol] if options[symbol]
      return ENV[symbol.to_s.upcase] if ENV.fetch(symbol.to_s.upcase, nil)
      raise Exception.new "#{symbol} is required" if raise_error
      nil
    end

    def client
      return @client if @client
      @client = Aws::ElasticBeanstalk::Client.new(
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region
      )
    end
  end
end