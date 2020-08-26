# Docker::Spec


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'docker-spec'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install docker-spec

## Usage

Add this line to the spec_helper.rb

```
require 'docker-spec'
```

And run rspec to build your docker containers

## Options are

| Option          | Description                                                                  |
|-----------------|------------------------------------------------------------------------------|
| :build_root     | wether to build the root directory or not                                    |
| :build_root     | wether to build the docker image                                             |
| :push_container | if the container should be pushed                                            |
| :account        | can be the registry URL or the dockerhub account name                        |
| :name           | the docker image / repository name                                           |
| :auth           | the auth key used to authenticate if is not dockerhub on ~/.docker/config.js |
| :serveraddress  | The server address to authenticate to if not dockerhub                       |
| :tag_db         | The file where to update the tag information                                 |
| :env            | an array of VAR=foo environment variables to pass when running               |
| :registry:      | registry credentials :username: :password:  :email:                          |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/docker-spec. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

