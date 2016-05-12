module Docker
  module Spec
    def self.docker_tests
      describe 'Running a docker container' do
        before(:all) do
          @config = DockerSpec.instance.config
          @image = Docker::Image.all.detect do |i|
            i.info['RepoTags'].include?(@config[:image_name] + ':latest')
          end
          @container = Docker::Container.all.select do |c|
            c.info["Names"] == [ "/" + @config[:container_name] ]
          end.first
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

        it 'Should not have exit processes' do
          expect(@container.logs(stdout: true)).to_not match(/exit/)
        end

        it 'Services supervisor should be running' do
          expect(process('supervisord')).to be_running
        end
      end
    end
  end
end
