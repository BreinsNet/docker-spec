require 'docker/spec/version'
require 'docker/spec/docker'
require 'serverspec'
require 'docker'
require 'pry'
require 'highline/import'
require 'popen4'
require 'colorize'
require 'yaml'
require 'logger'
require 'moneta'
require 'base64'
require 'singleton'
require 'pp'

# Documentation
class DockerSpec

  include Singleton

  attr_accessor :config, :test_failed, :container

  CONTAINER_RUN_WAIT_TIMEOUT = 60
  CONFIG_FILE = 'docker_spec.yml'
  ROOT_DIR = 'root'
  DOCKER_AUTH_FILE = '~/.docker/config.json'
  STDOUT.sync = true

  def run
    @config = nil
    @test_failed = false

    load_config
    build_root if @config[:build_root]
    build_docker_image if @config[:build_image]
    rspec_configure
  end

  def push
    @config[:push_container] = get_config(:push_container, 'DOCKER_SPEC_PUSH_CONTAINER',
                                                     'Push new tag? ')
    if @config[:push_container]

      @config[:tag_db] ||
        fail('tag_db is not defined in docker_spec.yml')

      # Load credentials from config file, or default docker config
      if @config[:dockerhub]
        @config[:dockerhub][:username] ||
          fail('dockerhub->username is not defined in docker_spec.yml')
        @config[:dockerhub][:password] ||
          fail('dockerhub->password is not defined in docker_spec.yml')
        @config[:dockerhub][:email] ||
          fail('dockerhub->email is not defined in docker_spec.yml')
      else
        @config[:dockerhub] = Hash.new
        docker_auth = JSON.parse(File.read(File.expand_path(DOCKER_AUTH_FILE)))
        auth_base64 = docker_auth['auths']['https://index.docker.io/v1/']['auth']
        @config[:dockerhub][:username] = Base64.decode64(auth_base64).split(':').first
        @config[:dockerhub][:password] = Base64.decode64(auth_base64).split(':').last
        @config[:dockerhub][:email] = docker_auth['auths']['https://index.docker.io/v1/']['email']
      end

      # Open key value store and get the current tag for this repo
      store = Moneta.new(:YAML, file: File.expand_path(@config[:tag_db]))
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

  def load_config
    File.exist?(CONFIG_FILE) || fail('Could not load docker_spec.yml')
    @config = YAML.load(File.read(CONFIG_FILE)) ||
              fail('docker_spec.yml is not a valid yml file')

    @config[:name] || fail('name is not defined in docker_spec.yml')
    @config[:account] || fail('account is not defined in docker_spec.yml')
    @config[:image_name] = format '%s/%s', @config[:account], @config[:name]
    @config[:build_image] = get_config(:build_image, 'DOCKER_SPEC_BUILD_DOCKER_IMAGE',
                                       'Build docker image? ')
    @config[:build_root] = get_config(:build_root, 'DOCKER_SPEC_BUILD_ROOT',
                                      'Rebuild root filesystem? ') if @config[:build_image]
    @config[:clear_cache] = get_config(:clear_cache, 'DOCKER_SPEC_CLEAR_CACHE',
                                       'Clear docker cache? ') if @config[:build_image]
    @config
  end

  def build_root
    command = <<EOF
bash -ec 'export WD=$(pwd) && export TMPDIR=$(mktemp -d -t docker-spec.XXXXXX) && 
cp -r root $TMPDIR/root && cd $TMPDIR && 
sudo chown root:root -R root && 
(cd root && sudo tar zcf ../root.tar.gz .) && 
sudo chown -R `id -u`:`id -g` root.tar.gz && 
cp root.tar.gz $WD &&
sudo  rm -rf $TMPDIR'
EOF
    system command if Dir.exist?(ROOT_DIR)
  end

  def build_docker_image
    puts
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

  def rspec_configure
    set :backend, :docker

    RSpec.configure do |rc|
      rc.fail_fast = true

      rc.after(:each) do |test|
        DockerSpec.instance.test_failed = true if test.exception
      end

      rc.before(:suite) do
        DockerSpec.instance.start_container
      end

      rc.after(:suite) do
        DockerSpec.instance.clean_up
        DockerSpec.instance.push unless DockerSpec.instance.test_failed
      end
    end
    Docker::Spec::docker_tests
  end

  def start_container
    # Run  the container with options
    opts = {}
    opts['HostConfig'] = { 'NetworkMode' => @config[:network_mode] } \
      unless @config[:network_mode].nil?

    opts['env'] = @config[:env] unless @config[:env].nil?
    opts['Image'] = @config[:image_name]
    @container = Docker::Container.create(opts).start
    Timeout::timeout(10) do
      loop do
        @container.refresh! 
        break if @container.info["State"]["Running"]
      end
    end


    # Check the logs, when it stops logging we can assume the container
    # is fully up and running
    log_size_ary = []
    CONTAINER_RUN_WAIT_TIMEOUT.times do
      log_size_ary << @container.logs(stdout: true).size
      break if log_size_ary.last(3).sort.uniq.size == 1 &&
               log_size_ary.last(3).sort.uniq.last > 0
      sleep 1
    end
    set :docker_container, @container.id
  end

  def delete_container
    @container.kill
    @container.delete
  end

  def clean_up
    # Keep container running
    @config[:keep_running] = get_config(:keep_running, 'DOCKER_SPEC_KEEP_RUNNING',
                                                   "\nKeep container running? ")
    if @config[:keep_running]
      puts "\nINFO: To connect to a running container: \n\n" \
        "docker exec -ti #{@container.info["Name"][1..-1]} bash"
    else
      delete_container
    end
  end

  def get_config(key, envvar, question)
    value = to_boolean(ENV[envvar])
    value = @config[key] if value.nil?
    value = agree(question, 'n') if value.nil?
    value
  end

  def to_boolean(str)
    str == 'true' unless str.nil?
  end
end
