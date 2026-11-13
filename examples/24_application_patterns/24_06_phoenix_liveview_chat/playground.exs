Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("chat_application.ex", __DIR__)
Code.require_file("chat_live.ex", __DIR__)

PhoenixPlayground.start(
  live: Jido.Examples.Patterns.LiveChat.Live,
  child_specs: Jido.Examples.Patterns.LiveChat.Live.child_specs(),
  live_reload: false
)
