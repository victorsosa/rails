{module, test} = QUnit
{testURL, createConsumer} = ActionCable.TestHelpers

module "ActionCable.Consumer", ->
  test "#connect", (assert) ->
    done = assert.async()

    createConsumer testURL, (consumer, server) ->
      server.on "connection", ->
        clients = server.clients()
        assert.equal clients.length, 1
        assert.equal clients[0].readyState, WebSocket.OPEN
        done()

      consumer.connect()

  test "#disconnect", (assert) ->
    done = assert.async()

    createConsumer testURL, (consumer, server) ->
      server.on "connection", ->
        clients = server.clients()
        assert.equal clients.length, 1

        clients[0].addEventListener "close", (event) ->
          assert.equal event.type, "close"
          done()

        consumer.disconnect()

      consumer.connect()
