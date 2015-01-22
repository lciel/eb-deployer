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
        print ret[:environments][0].cname
      else
        print ''
      end
    end

    desc 'get_endpoint_url target_environment', 'Get an endpoint url by target environment name'
    def get_endpoint_url(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      if ret[:environments].length == 1
        print ret[:environments][0].endpoint_url
      else
        print ''
      end
    end

    desc 'check_exist target_environment', 'Get true if exist target environment name'
    def check_exist(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      if ret[:environments].length == 1
        print true
      else
        print false
      end
    end

    option :template_name
    option :tier
    option :cname
    option :option_settings_file
    option :option_settings
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
      print ret[:environment_id]
    end

    desc 'status environment_name', 'Get status by target environment name'
    def status(environment_name)
      print status_value(environment_name).to_hash.to_json
    end

    option :timeout
    desc 'wait_up environment_name', 'Wait environment ready and green'
    def wait_up(environment_name)
      start_time = Time.now
      t = 1200
      t = timeout if timeout != 0

      interval = 5
      counter = request_failed = health_failed = 0

      request_failed_limit = 3
      health_failed_limit = 5
      timeout_count_limit = t / interval

      loop do
        st = status_value(environment_name)

        if st.nil?
          request_failed += 1
          if request_failed > request_failed_limit
            puts "\nFailed to up #{environment_name}: Environment not found"
            exit 1
          end
          puts "Environment not found: count: #{request_failed}"
        else
          break if st.status.downcase == 'ready' && st.health.downcase == 'green'
          unless st.status.downcase == 'launching' || st.status.downcase == 'ready'
            puts "\nFailed to up #{environment_name}: Unexpected status: #{st.status}, health: #{st.health}"
            exit 1
          end
          health_failed += 1 if st.health.downcase == 'red' || st.health.downcase == 'yellow'
          if health_failed > health_failed_limit
            puts "\nFailed to up #{environment_name}: Bad health: #{st.health}, status: #{st.status}"
            exit 1
          end
        end

        if counter >= timeout_count_limit
          puts "\nFailed to up #{environment_name}: Timeout"
          exit 1
        end

        counter += 1
        print '.'
        sleep interval
      end
      puts "\nSuccess to up #{environment_name}! (#{(Time.now - start_time).to_i} sec)"
    end

    private

    def status_value(environment_name)
      ret = client.describe_environments(
        application_name: application_name,
        environment_names: [environment_name]
      )
      ret[:environments][0]
    end

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

    def timeout
      t = fetch_attribute(:timeout, false)
      t.to_i
    end

    def option_settings
      options = fetch_attribute(:option_settings, false)
      unless options
        option_file = fetch_attribute(:option_settings_file, false)
        return nil unless option_file
        if File.exist?(option_file)
          options = File.read(option_file)
        else
          raise Exception.new "#{option_file} is not found."
        end
      end
      return nil unless options
      eval(options)
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
