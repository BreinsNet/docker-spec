require 'docker/spec/version'
require 'docker/spec/docker'
require 'serverspec'
require 'docker'
require 'pry'
require 'timeout'
require 'highline/import'
require 'popen4'
require 'colorize'
require 'yaml'
require 'logger'
require 'moneta'
require 'pp'

# Documentation
module DockerSpec
  CONTAINER_RUN_WAIT_TIMEOUT = 60
  CONFIG_FILE = 'docker_spec.yml'
  ROOT_DIR = 'root'
  STDOUT.sync = true

  def self.run
    load_config
    build_root if @config[:build_root]
    build_docker_image
    rspec_run
  end

  def self.push
    @config[:push_container] = DockerSpec.get_config(:push_container, 'DOCKER_SPEC_PUSH_CONTAINER',
                                                     'Push new tag? ')
    if @config[:push_container]

      @config[:tag_db] ||
        fail('tag_db is not defined in docker_spec.yml')
      @config[:dockerhub] ||
        fail('dockerhub is not defined in docker_spec.yml')
      @config[:dockerhub][:username] ||
        fail('dockerhub->username is not defined in docker_spec.yml')
      @config[:dockerhub][:password] ||
        fail('dockerhub->password is not defined in docker_spec.yml')
      @config[:dockerhub][:email] ||
        fail('dockerhub->email is not defined in docker_spec.yml')

      # Open key value store and get the current tag for this repo
      store = Moneta.new(:YAML, file: @config[:tag_db])
      current_tag = store.key?(@config[:image_name]) ? store[@config[:image_name]].to_i : 0
      new_tag = current_tag + 1

      image = Docker::Image.all.detect do |i|
        i.info['RepoTags'].include?(@config[:image_name] + ':latest')
      end

      # Login to docker hub and push latest and new_tag
      Docker.authenticate! username: @config[:dockerhub][:username],
                           password: @config[:dockerhub][:password],
                           email: @config[:dockerhub][:email]

      image.tag repo: @config[:image_name], tag: new_tag, force: true
      puts "\nINFO: pushing #{@config[:image_name]}:#{new_tag} to DockerHub"
      image.push nil, tag: new_tag

      image.tag repo: @config[:image_name], tag: 'latest', force: true
      puts "INFO: pushing #{@config[:image_name]}:latest to DockerHub"
      image.push nil, tag: 'latest'

      # Store the new tag in the tag_db
      store[@config[:image_name]] = new_tag
      store.close
    end
  end

  def self.load_config
    File.exist?(CONFIG_FILE) || fail('Could not load docker_spec.yml')
    @config = YAML.load(File.read(CONFIG_FILE)) ||
              fail('docker_spec.yml is not a valid yml file')

    @config[:name] || fail('name is not defined in docker_spec.yml')
    @config[:account] || fail('account is not defined in docker_spec.yml')
    @config[:image_name] = format '%s/%s', @config[:account], @config[:name]
    @config[:container_name] = format 'docker_spec-%s', @config[:name]
    @config[:build_root] = DockerSpec.get_config(:build_root, 'DOCKER_SPEC_BUILD_ROOT',
                                                 'Rebuild root filesystem? ')
    @config[:clear_cache] = DockerSpec.get_config(:clear_cache, 'DOCKER_SPEC_CLEAR_CACHE',
                                                  'Clear docker cache? ')
    @config
  end

  def self.build_root
    system 'bash -ec \'sudo chown root:root -R root &&' \
           '(cd root && sudo tar zcf ../root.tar.gz .) && ' \
           'sudo chown -R `id -u`:`id -g` root.tar.gz root\'' \
           if Dir.exist?(ROOT_DIR)
  end

  def self.build_docker_image
    # Rebuild the cache filesystem
    build_args = ''
    build_args += ' --no-cache' if @config[:clear_cache]

    # Build the docker image
    build_cmd = "docker build -t #{@config[:image_name]} #{build_args} ."
    status = POpen4.popen4(build_cmd) do |stdout, stderr, _stdin|
      stdout.each { |line| puts line }
      stderr.each { |line| puts line.red }
    end
    fail("#{build_cmd} failed") if status.exitstatus != 0
  end

  def self.rspec_run
    set :backend, :docker

    RSpec.configure do |rc|
      rc.fail_fast = true

      rc.before(:suite) do
        DockerSpec.delete_container
        DockerSpec.start_container
      end

      rc.after(:suite) do
        DockerSpec.clean_up
        DockerSpec.push
      end
    end
    docker_tests
  end

  def self.start_container
    # Run  the container with options
    opts = {}
    opts['HostConfig'] = { 'NetworkMode' => @config[:network_mode] } \
      unless @config[:network_mode].nil?

    opts['env'] = @config[:env] unless @config[:env].nil?
    opts['Image'] = @config[:image_name]
    opts['name'] = @config[:container_name]
    container = Docker::Container.create(opts).start

    # Check the logs, when it stops logging we can assume the container
    # is fully up and running
    log_size_ary = []
    CONTAINER_RUN_WAIT_TIMEOUT.times do
      log_size_ary << container.logs(stdout: true).size
      break if log_size_ary.last(3).sort.uniq.size == 1 &&
               log_size_ary.last(3).sort.uniq.last > 0
      sleep 1
    end
    set :docker_container, container.id
  end

  def self.delete_container
    filters = { name: [@config[:container_name]] }.to_json
    Docker::Container.all(all: true, filters: filters).each do |c|
      c.kill
      c.delete
    end
  end

  def self.clean_up
    # Keep container running
    @config[:keep_running] = DockerSpec.get_config(:keep_running, 'DOCKER_SPEC_KEEP_RUNNING',
                                                   'Keep container running? ')
    if @config[:keep_running]
      puts "\nINFO: To connect to a running container: \n\n" \
        "docker exec -ti #{@config[:container_name]} bash"
    else
      delete_container
    end
  end

  def self.get_config(key, envvar, question)
    value = to_boolean(ENV[envvar])
    value ||= @config[key]
    value ||= agree(question, 'n') if value.nil?
    value
  end

  def self.to_boolean(str)
    str == 'true' unless str.nil?
  end
end
