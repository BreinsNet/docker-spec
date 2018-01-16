require 'spec_helper'

describe 'docker spec test' do
  it 'should be able to run commands' do
    expect(command('ls /').exit_status).to eq 0
  end

  it 'should add the files from root dir' do
    expect(command('ls /file.test').exit_status).to eq 0
  end

  it 'should have environment variables defined on docker_spec.yml' do
    expect(command('echo $TEST_ENV').stdout.chomp).to eq 'Test'
  end
end
