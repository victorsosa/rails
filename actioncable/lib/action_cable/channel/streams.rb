module ActionCable
  module Channel
    # Streams allow channels to route broadcastings to the subscriber. A broadcasting is, as discussed elsewhere, a pubsub queue where any data
    # placed into it is automatically sent to the clients that are connected at that time. It's purely an online queue, though. If you're not
    # streaming a broadcasting at the very moment it sends out an update, you will not get that update, if you connect after it has been sent.
    #
    # Most commonly, the streamed broadcast is sent straight to the subscriber on the client-side. The channel just acts as a connector between
    # the two parties (the broadcaster and the channel subscriber). Here's an example of a channel that allows subscribers to get all new
    # comments on a given page:
    #
    #   class CommentsChannel < ApplicationCable::Channel
    #     def follow(data)
    #       stream_from "comments_for_#{data['recording_id']}"
    #     end
    #
    #     def unfollow
    #       stop_all_streams
    #     end
    #   end
    #
    # Based on the above example, the subscribers of this channel will get whatever data is put into the,
    # let's say, `comments_for_45` broadcasting as soon as it's put there.
    #
    # An example broadcasting for this channel looks like so:
    #
    #   ActionCable.server.broadcast "comments_for_45", author: 'DHH', content: 'Rails is just swell'
    #
    # If you have a stream that is related to a model, then the broadcasting used can be generated from the model and channel.
    # The following example would subscribe to a broadcasting like `comments:Z2lkOi8vVGVzdEFwcC9Qb3N0LzE`
    #
    #   class CommentsChannel < ApplicationCable::Channel
    #     def subscribed
    #       post = Post.find(params[:id])
    #       stream_for post
    #     end
    #   end
    #
    # You can then broadcast to this channel using:
    #
    #   CommentsChannel.broadcast_to(@post, @comment)
    #
    # If you don't just want to parlay the broadcast unfiltered to the subscriber, you can also supply a callback that lets you alter what is sent out.
    # The below example shows how you can use this to provide performance introspection in the process:
    #
    #   class ChatChannel < ApplicationCable::Channel
    #     def subscribed
    #       @room = Chat::Room[params[:room_number]]
    #
    #       stream_for @room, coder: ActiveSupport::JSON do |message|
    #         if message['originated_at'].present?
    #           elapsed_time = (Time.now.to_f - message['originated_at']).round(2)
    #
    #           ActiveSupport::Notifications.instrument :performance, measurement: 'Chat.message_delay', value: elapsed_time, action: :timing
    #           logger.info "Message took #{elapsed_time}s to arrive"
    #         end
    #
    #         transmit message
    #       end
    #     end
    #   end
    #
    # You can stop streaming from all broadcasts by calling #stop_all_streams.
    module Streams
      extend ActiveSupport::Concern

      included do
        on_unsubscribe :stop_all_streams
      end

      # Start streaming from the named <tt>broadcasting</tt> pubsub queue. Optionally, you can pass a <tt>callback</tt> that'll be used
      # instead of the default of just transmitting the updates straight to the subscriber.
      # Pass `coder: ActiveSupport::JSON` to decode messages as JSON before passing to the callback.
      # Defaults to `coder: nil` which does no decoding, passes raw messages.
      def stream_from(broadcasting, callback = nil, coder: nil, &block)
        broadcasting = String(broadcasting)
        # Don't send the confirmation until pubsub#subscribe is successful
        defer_subscription_confirmation!

        if user_handler = callback || block
          user_handler = -> message { handler.(coder.decode(message)) } if coder
          handler = -> message do
            connection.worker_pool.async_invoke(user_handler, :call, message)
          end
        else
          handler = default_stream_handler(broadcasting, coder: coder)
        end

        streams << [ broadcasting, handler ]

        connection.server.event_loop.post do
          pubsub.subscribe(broadcasting, handler, lambda do
            transmit_subscription_confirmation
            logger.info "#{self.class.name} is streaming from #{broadcasting}"
          end)
        end
      end

      # Start streaming the pubsub queue for the <tt>model</tt> in this channel. Optionally, you can pass a
      # <tt>callback</tt> that'll be used instead of the default of just transmitting the updates straight
      # to the subscriber.
      #
      # Pass `coder: ActiveSupport::JSON` to decode messages as JSON before passing to the callback.
      # Defaults to `coder: nil` which does no decoding, passes raw messages.
      def stream_for(model, callback = nil, coder: nil, &block)
        stream_from(broadcasting_for([ channel_name, model ]), callback || block, coder: coder)
      end

      # Unsubscribes all streams associated with this channel from the pubsub queue.
      def stop_all_streams
        streams.each do |broadcasting, callback|
          pubsub.unsubscribe broadcasting, callback
          logger.info "#{self.class.name} stopped streaming from #{broadcasting}"
        end.clear
      end

      private
        delegate :pubsub, to: :connection

        def streams
          @_streams ||= []
        end

        def default_stream_handler(broadcasting, coder:)
          coder ||= ActiveSupport::JSON

          -> (message) do
            transmit coder.decode(message), via: "streamed from #{broadcasting}"
          end
        end
    end
  end
end
