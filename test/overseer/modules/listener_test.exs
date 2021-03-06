defmodule OpenAperture.Overseer.Modules.ListenerTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Modules.Listener
  alias OpenAperture.ManagerApi.MessagingExchangeModule
  alias OpenAperture.ManagerApi.Response
  
  alias OpenAperture.Messaging.ConnectionOptionsResolver
  alias OpenAperture.Messaging.AMQP.ConnectionPool
  alias OpenAperture.Messaging.AMQP.ConnectionPools  
  alias OpenAperture.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions
  alias OpenAperture.Messaging.AMQP.QueueBuilder
  
  # ===================================
  # process_event tests

  test "process_event - unknown event" do
    payload = %{
      event_type: :bogus
    }

    assert Listener.process_event(payload, "delivery_tag")
  end

  test "process_event - status event" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :create_module!, fn _, _ -> true end)

    module = %{
      hostname: System.get_env("HOSTNAME"),
      type: Application.get_env(:openaperture_overseer_api, :module_type),
      status: :active,
      workload: []      
    }

    payload = %{
      event_type: :status
    }

    module = %{
      "hostname" => "123abc"
    }

    assert Listener.process_event(payload, "delivery_tag")
  after
    :meck.unload(MessagingExchangeModule)    
  end  

  test "process_event - status event failed" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :create_module!, fn _, _ -> false end)
    :meck.expect(MessagingExchangeModule, :create_module, fn _, _ -> %Response{status: 400, body: "{\"errors\": []}"} end)

    module = %{
      hostname: System.get_env("HOSTNAME"),
      type: Application.get_env(:openaperture_overseer_api, :module_type),
      status: :active,
      workload: []      
    }

    payload = %{
      event_type: :status
    }

    module = %{
      "hostname" => "123abc"
    }

    assert Listener.process_event(payload, "delivery_tag")
  after
    :meck.unload(MessagingExchangeModule)    
  end    

  #=========================
  # handle_cast({:start_listening})

  test "handle_cast({:start_listening}) - success" do
    :meck.new(ConnectionOptionsResolver, [:passthrough])
    :meck.expect(ConnectionOptionsResolver, :get_for_broker, fn _, _ -> %AMQPConnectionOptions{} end)

    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:ok, %{}} end)

    :meck.new(QueueBuilder, [:passthrough])
    :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

    module = %{
      hostname: "myhost",
      type: :test,
      status: :active,
      workload: []      
    }

    state = %{module: module}

    {:noreply, returned_state} = Listener.handle_cast({:start_listening}, state)
    assert returned_state != nil
    assert returned_state[:subscription_handler] != nil
  after
    :meck.unload(ConnectionOptionsResolver)
    :meck.unload(ConnectionPools)
    :meck.unload(ConnectionPool)
  end   

  test "handle_cast({:start_listening}) - failure" do
    :meck.new(ConnectionOptionsResolver, [:passthrough])
    :meck.expect(ConnectionOptionsResolver, :get_for_broker, fn _, _ -> %AMQPConnectionOptions{} end)

    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:error, "bad news bears"} end)

    :meck.new(QueueBuilder, [:passthrough])
    :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

    module = %{
      hostname: "myhost",
      type: :test,
      status: :active,
      workload: []      
    }

    state = %{module: module}

    {:noreply, returned_state} = Listener.handle_cast({:start_listening}, state)
    assert returned_state != nil
    assert returned_state[:subscription_handler] == nil
  after
    :meck.unload(ConnectionOptionsResolver)
    :meck.unload(ConnectionPools)
    :meck.unload(ConnectionPool)
  end  
end