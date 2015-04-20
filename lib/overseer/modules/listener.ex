require Logger

defmodule OpenAperture.Overseer.Modules.Listener do
	use GenServer

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  alias OpenAperture.Overseer.MessageManager
  alias OpenAperture.Overseer.Configuration

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchangeModule

  @moduledoc """
  This module contains the logic to subscribe and unsubscribe from Module-specific queues
  """  

	@connection_options nil
	use OpenAperture.Messaging

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  The `module` option defines the Module options Map

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t()}   
  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module}, [])
  end

  @doc """
  Method to retrieve the module definition within the pid

  ## Options

  The `listener` option defines the listener PID

  Current module definition
  """
  @spec get_module(pid) :: Map
  def get_module(listener) do
    GenServer.call(listener, {:get_module})
  end

  @doc """
  Method to update the module definition within the pid

  ## Options

  The `listener` option defines the listener PID

  The `module` option defines the system module map

  Current module definition
  """
  @spec set_module(pid, Map) :: Map
  def set_module(listener, module) do
    GenServer.call(listener, {:set_module, module})
  end

  @doc """
  Method to subscribe from the module queue

  ## Options

  The `listener` option defines the listener PID

  :ok
  """
  @spec start_listening(pid) :: :ok
  def start_listening(module) do
    GenServer.cast(module, {:start_listening})
  end

  @doc """
  Method to unsubscribe from the module queue

  ## Options

  The `listener` option defines the listener PID

  :ok
  """
  @spec stop_listening(pid) :: :ok
  def stop_listening(listener) do
    GenServer.cast(listener, {:stop_listening})
  end

  @doc """
  GenServer callback for handling the :start_listening event.  This method
  starts listener (i.e. subscribes) to events coming from the MessagingExchangeModule

  {:noreply, state}
  """
  @spec handle_cast({:start_listening}, Map) :: {:noreply, Map}
  def handle_cast({:start_listening}, state) do
    Logger.debug("[Overseer][Listener][#{state[:module]["hostname"]}] Starting event listener...")
    event_queue = QueueBuilder.build(ManagerApi.get_api, "module_#{state[:module]["hostname"]}", Configuration.get_current_exchange_id, [durable: false])

    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
    subscription_handler = case subscribe(options, event_queue, fn(payload, _meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = async_info) -> 
      MessageManager.track(async_info)
      process_event(payload, delivery_tag, state[:module]) 
      OpenAperture.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
    end) do
      {:ok, subscription_handler} -> subscription_handler
      {:error, reason} -> 
        Logger.error("[Overseer][Listener][#{state[:module]["hostname"]}] Failed to start event listener:  #{inspect reason}")
        nil
    end

    {:noreply, Map.put(state, :subscription_handler, subscription_handler)}
  end

  @doc """
  GenServer callback for handling the :retrieve_module_list event.  This method
  will retrieve MessagingExchangeModules for the configured messaging exchange.

  {:noreply, new modules list}
  """
  @spec handle_cast({:stop_listening}, Map) :: {:noreply, List}
  def handle_cast({:stop_listening}, state) do
    Logger.debug("[Overseer][Listener][#{state[:module]["hostname"]}] Stopping event listener")
    
    unless state[:subscription_handler] == nil do
      options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
      unsubscribe(options, state[:subscription_handler])
    end
    {:noreply, state}
  end

  @doc """
  GenServer callback for handling the :set_workflow event.  This method
  will store the current worklow into the server's state.

  {:noreply, state}
  """
  @spec handle_call({:get_module}, term, Map) :: {:reply, Map, Map}
  def handle_call({:get_module}, _from, state) do
    {:noreply, state[:module], state}
  end

  @doc """
  GenServer callback for handling the :set_module event.  This method
  will store the module into the server's state.

  {:noreply, state}
  """
  @spec handle_call({:set_module, Map}, term, Map) :: {:reply, Map, Map}
  def handle_call({:set_module, module}, _from, state) do
    {:noreply, module, Map.put(state, :module, module)}
  end
  @doc """
  Method to process an incoming request

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec process_event(Map, String.t(), Map) :: term
  def process_event(%{event_type: :status} = payload, delivery_tag, module) do
    Logger.debug("[Overseer][Listener][#{state[:module]["hostname"]}] Received a status event from module")
    case MessagingExchangeModule.create_module!(Configuration.get_current_exchange_id, payload) do
      true -> Logger.debug("[Overseer][Listener][#{state[:module]["hostname"]}] Successfully updated module")
      false -> Logger.error("[Overseer][Listener][#{state[:module]["hostname"]}] Failed to update module")
    end
  end

  @doc """
  Method to process an incoming request

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec process_event(Map, String.t(), Map) :: term
  def process_event(%{event_type: type} = payload, delivery_tag, module) do
    Logger.debug("[Overseer][Listener][#{state[:module]["hostname"]}] Received an unknown event:  #{inspect type}")
  end
end