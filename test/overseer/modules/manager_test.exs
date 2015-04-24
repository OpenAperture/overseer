defmodule OpenAperture.Overseer.Modules.ManagerTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Modules.Manager
  alias OpenAperture.ManagerApi.MessagingExchangeModule
  
  # ===================================
  # inactivate_listeners tests

  test "inactivate_listeners no modules" do
    Manager.inactivate_listeners([])
  end

  test "inactivate_listeners active module" do
    now = Date.now #utc
    now_string = DateFormat.format!(now, "{RFC1123}")

    Manager.inactivate_listeners([%{"updated_at" => now_string}])
  end

  test "inactivate_listeners inactive module" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :create_module!, fn _,_ -> true end)

    now = Date.now #utc
    now_secs = Date.convert(now, :secs) #since epoch

    lookback_seconds = now_secs-(15*60)
    lookback = Date.from(lookback_seconds, :secs, :epoch)
    lookback_string = DateFormat.format!(lookback, "{RFC1123}")

    Manager.inactivate_listeners([%{"updated_at" => lookback_string}])
  after
    :meck.unload(MessagingExchangeModule)
  end  
  
  test "inactivate_listeners delete module" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :delete_module!, fn _,_ -> true end)

    now = Date.now #utc
    now_secs = Date.convert(now, :secs) #since epoch

    lookback_seconds = now_secs-(25*60)
    lookback = Date.from(lookback_seconds, :secs, :epoch)
    lookback_string = DateFormat.format!(lookback, "{RFC1123}")

    Manager.inactivate_listeners([%{"updated_at" => lookback_string}])
  after
    :meck.unload(MessagingExchangeModule)
  end   
end