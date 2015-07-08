defmodule OpenAperture.Overseer.Components.ComponentsMgrTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Components.ComponentsMgr
  alias OpenAperture.Overseer.Components.ComponentMgr

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange
  alias OpenAperture.ManagerApi.SystemComponentRef

  alias OpenAperture.Overseer.Configuration
  
  # ===================================
  # resolve_system_components tests

  test "resolve_system_components - invalid configured components" do
    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> nil end)

    state = %{}

    returned_state = ComponentsMgr.resolve_system_components(state)
    assert returned_state == state  
  after
    :meck.unload(MessagingExchange)
  end

  test "resolve_system_components - no configured components" do
    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> [] end)

    state = %{}

    returned_state = ComponentsMgr.resolve_system_components(state)
    assert returned_state == state  
  after
    :meck.unload(MessagingExchange)
  end

  test "resolve_system_components - no existing manager with component" do
    component = %{
      "type" => "test"
    }
    components = [component]

    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> components end)

    {:ok, mgr} = Agent.start_link(fn -> %{} end)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :start_link, fn _ -> {:ok, mgr} end)

    state = %{
      managers: %{}
    }

    returned_state = ComponentsMgr.resolve_system_components(state)
    assert returned_state[:managers]["test"] == mgr
  after
    :meck.unload(MessagingExchange)
    :meck.unload(ComponentMgr)
  end

  test "resolve_system_components - no existing manager with component mgr failing to start" do
    component = %{
      "type" => "test",
      "id" => "#{UUID.uuid1()}"
    }
    components = [component]

    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> components end)

    {:ok, mgr} = Agent.start_link(fn -> %{} end)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :start_link, fn _ -> {:error, "bad news bears"} end)

    state = %{
      managers: %{}
    }

    returned_state = ComponentsMgr.resolve_system_components(state)
    assert returned_state[:managers]["test"] == nil
  after
    :meck.unload(MessagingExchange)
    :meck.unload(ComponentMgr)
  end

  test "resolve_system_components - existing manager with component" do
    component = %{
      "type" => "test",
      "id" => "#{UUID.uuid1()}"
    }
    components = [component]

    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> components end)

    {:ok, existing_mgr} = Agent.start_link(fn -> %{} end)
    state = %{
      managers: %{
        "test" => existing_mgr
      }
    }

    returned_state = ComponentsMgr.resolve_system_components(state)
    assert returned_state[:managers]["test"] == existing_mgr
  after
    :meck.unload(MessagingExchange)
  end

  test "get_mgr_for_component_type - existing manager with component" do
    component = %{
      "type" => "test",
      "id" => "#{UUID.uuid1()}"
    }
    components = [component]

    :meck.new(MessagingExchange, [:passthrough])
    :meck.expect(MessagingExchange, :exchange_components!, fn _,_ -> components end)

    {:ok, existing_mgr} = Agent.start_link(fn -> %{} end)
    state = %{
      managers: %{
      }
    }

    Agent.start_link(fn -> %{} end, name: :ComponentMgrStore)
    returned_state = ComponentsMgr.resolve_system_components(state)
    returned_mgr = ComponentsMgr.get_mgr_for_component_type(component["type"])
    assert returned_mgr == returned_state[:managers][component["type"]]
  after
    :meck.unload(MessagingExchange)
  end
end