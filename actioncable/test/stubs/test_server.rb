require 'ostruct'

class TestServer
  include ActionCable::Server::Connections

  attr_reader :logger, :config

  def initialize
    @logger = ActiveSupport::TaggedLogging.new ActiveSupport::Logger.new(StringIO.new)
    @config = OpenStruct.new(log_tags: [], subscription_adapter: SuccessAdapter)
  end

  def pubsub
    @config.subscription_adapter.new(self)
  end

  def send_async
  end
end
