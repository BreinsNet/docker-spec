module Docker
  module Spec
    def self.docker_tests
      describe 'Running a docker container', test: :default do
        before(:all) do
          @container = DockerSpec.instance.container
          @image = @container.info["Image"]
        end

        it 'should be available' do
          expect(@image).to_not be_nil
        end

        it 'should have state running' do
          expect(@container.json['State']['Running']).to be true
        end

        it 'Should stay running' do
          expect(@container.json['State']['Running']).to be true
        end

        it 'Services supervisor should be running' do
          expect(process('supervisord')).to be_running
        end

        it 'Should not have exit processes' do
          if @container.logs(stdout: true).match(/exit/)
            logs = command('cat /var/log/supervisor/*').stdout
            File.open('supervisor-err.log', 'w+').write logs
          end
          expect(@container.logs(stdout: true)).to_not match(/exit/)
        end
      end
    end
  end
end
