require Logger

defmodule OpenAperture.Overseer.Modules.Listener do
	use GenServer

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  #alias OpenAperture.Overseer.MessageManager
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
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link() do
    case GenServer.start_link(__MODULE__, %{}, []) do
      {:ok, listener} ->
        if Application.get_env(:autostart, :start_listening, true) do
          GenServer.cast(listener, {:start_listening})
        end
        {:ok, listener}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  GenServer callback for handling the :start_listening event.  This method
  starts listener (i.e. subscribes) to events coming from the MessagingExchangeModule

  {:noreply, state}
  """
  @spec handle_cast({:start_listening}, Map) :: {:noreply, Map}
  def handle_cast({:start_listening}, state) do
    Logger.debug("[Listener] Starting event listener...")
    event_queue = QueueBuilder.build(ManagerApi.get_api, Configuration.get_current_system_modules_queue_name, Configuration.get_current_exchange_id)

    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
    subscription_handler = case subscribe(options, event_queue, fn(payload, _meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) -> 
      #Logger.debug("[Listener] Received message #{delivery_tag}")
      #MessageManager.track(async_info)
      process_event(payload, delivery_tag)
      SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
      #MessageManager.remove(delivery_tag)
    end) do
      {:ok, subscription_handler} -> 
        Logger.debug("[Listener] Successfully started event listener #{inspect subscription_handler}")
        subscription_handler
      {:error, reason} -> 
        Logger.error("[Listener] Failed to start event listener:  #{inspect reason}")
        nil
    end

    {:noreply, Map.put(state, :subscription_handler, subscription_handler)}
  end

  @doc """
  Method to process an incoming request

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec process_event(Map, String.t()) :: term
  def process_event(%{event_type: :status} = payload, _delivery_tag) do
    Logger.debug("Received a status event from module #{payload[:hostname]}")

    new_module = %{
      hostname: payload[:hostname],
      type: payload[:type],
      status: payload[:status],
      workload: payload[:workload]
    }

    case MessagingExchangeModule.create_module!(Configuration.get_current_exchange_id, new_module) do
      nil -> 
        response = MessagingExchangeModule.create_module(Configuration.get_current_exchange_id, new_module)
        if response.success? do
          Logger.debug("[Listener] Successfully updated module #{payload[:hostname]}")
          true
        else
          Logger.error("[Listener] Failed to update module #{payload[:hostname]}!  module - #{inspect payload}, status - #{inspect response.status}, errors - #{inspect response.raw_body}")
          false      
        end
      _ -> Logger.debug("[Listener] Successfully updated module #{payload[:hostname]}")
    end
  end

  @doc """
  Method to process an incoming request

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec process_event(Map, String.t()) :: term
  def process_event(%{event_type: type} = _payload, _delivery_tag) do
    Logger.debug("[Listener] Received an unknown event:  #{inspect type}")
  end
end