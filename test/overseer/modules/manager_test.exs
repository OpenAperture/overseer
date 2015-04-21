defmodule OpenAperture.Overseer.Modules.ManagerTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Modules.Manager
  alias OpenAperture.Overseer.Modules.Listener
  alias OpenAperture.ManagerApi.MessagingExchangeModule
  
  # ===================================
  # inactivate_listeners tests

  test "inactivate_listeners no modules" do
    :meck.new(Listener, [:passthrough])
    :meck.expect(Listener, :get_module, fn _ -> %{
      "updated_at" => "#{:httpd_util.rfc1123_date(:calendar.universal_time())}"
    } 
    end)

    state = %{
      listeners: %{},
      modules: %{},
    }
    Manager.inactivate_listeners(state)
  after
    :meck.unload(Listener)
  end

  test "inactivate_listeners active module" do
    now = Date.now #utc
    now_string = DateFormat.format!(now, "{RFC1123}")

    state = %{
      listeners: %{"123" => %{}},
      modules: %{"123" => %{"updated_at" => now_string}},
    }
    Manager.inactivate_listeners(state)
  end

  test "inactivate_listeners inactive module" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :create_module!, fn _,_ -> true end)

    now = Date.now #utc
    now_secs = Date.convert(now, :secs) #since epoch

    lookback_seconds = now_secs-(15*60)
    lookback = Date.from(lookback_seconds, :secs, :epoch)
    lookback_string = DateFormat.format!(lookback, "{RFC1123}")

    :meck.new(Listener, [:passthrough])
    :meck.expect(Listener, :set_module, fn _,_ -> :ok end)

    state = %{
      listeners: %{"123" => %{"updated_at" => lookback_string}},
      modules: %{"123" => %{"updated_at" => lookback_string}},
    }
    
    Manager.inactivate_listeners(state)
  after
    :meck.unload(Listener)
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

    state = %{
      listeners: %{"123" => %{"updated_at" => lookback_string}},
      modules: %{"123" => %{"updated_at" => lookback_string}},
    }
    
    Manager.inactivate_listeners(state)
  after
    :meck.unload(MessagingExchangeModule)
  end   

  #=====================
  # stop_listeners tests

  test "stop_listeners - stop listener" do
    :meck.new(Listener, [:passthrough])
    :meck.expect(Listener, :stop_listening, fn _ -> :ok end)

    state = %{
      listeners: %{"123abc" => %{}},
      modules: %{"123abc" => %{}},
    }

    modules = [%{"hostname" => "123abc"}]
    returned_state = Manager.stop_listeners(state, modules)
    assert returned_state != nil
    assert returned_state[:listeners] != nil
    assert returned_state[:listeners]["123abc"] == nil
  after
    :meck.unload(Listener)
  end

  test "stop_listeners - empty list" do
    state = %{
      listeners: %{},
      modules: %{},
    }

    modules = []
    returned_state = Manager.stop_listeners(state, modules)
    assert returned_state != nil
    assert returned_state[:listeners] != nil
  end

  test "stop_listeners - nil" do
    state = %{
      listeners: %{},
      modules: %{},
    }

    returned_state = Manager.stop_listeners(state, nil)
    assert returned_state != nil
    assert returned_state[:listeners] != nil
  end  

  #=====================
  # start_listeners tests

  test "start_listeners - already started listener" do
    state = %{
      listeners: %{"123abc" => %{}},
      modules: %{"123abc" => %{}},
    }

    modules = [%{"hostname" => "123abc"}]
    returned_state = Manager.start_listeners(state, modules)
    assert returned_state != nil
    assert returned_state[:listeners] != nil
    assert returned_state == state
  end

  test "start_listeners - started listener" do
    :meck.new(Listener, [:passthrough])
    :meck.expect(Listener, :start_link, fn _ -> {:ok, %{}} end)
    :meck.expect(Listener, :start_listening, fn _ -> :ok end)

    state = %{
      listeners: %{},
      modules: %{},
    }

    modules = [%{"hostname" => "123abc"}]
    returned_state = Manager.start_listeners(state, modules)
    assert returned_state != nil
    assert returned_state[:listeners] != nil
    assert returned_state[:listeners]["123abc"] == %{}
  after
    :meck.unload(Listener)
  end

  test "start_listeners - empty list" do
    state = %{
      listeners: %{},
      modules: %{},
    }

    modules = []
    returned_state = Manager.start_listeners(state, modules)
    assert returned_state != nil
    assert returned_state[:listeners] != state
  end

  #=====================
  # find_deleted_modules tests

  test "find_deleted_modules - no modules to delete" do
    state = %{
      listeners: %{"123abc" => %{}},
      modules: %{"123abc" => %{}},
    }

    modules = [%{"hostname" => "123abc"}]
    returned_list = Manager.find_deleted_modules(state, modules)
    assert returned_list == []
  end

  test "find_deleted_modules - modules to delete" do
    :meck.new(Listener, [:passthrough])
    :meck.expect(Listener, :get_module, fn _ -> %{"hostname" => "123abc"} end)

    state = %{
      listeners: %{"123abc" => %{}},
      modules: %{"123abc" => %{}},
    }

    modules = []
    returned_list = Manager.find_deleted_modules(state, modules)
    assert returned_list == [%{"hostname" => "123abc"}]
  after
    :meck.unload(Listener)    
  end  
end