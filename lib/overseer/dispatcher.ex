#
# == dispatcher.ex
#
# This module contains the logic to dispatch Overseer messsages to the appropriate GenServer(s)
#
require Logger

defmodule OpenAperture.Overseer.Dispatcher do
	use GenServer

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  alias OpenAperture.Overseer.MessageManager
  alias OpenAperture.Overseer.Configuration

  alias OpenAperture.ManagerApi

  @moduledoc """
  This module contains the logic to dispatch Overseer messsages to the appropriate GenServer(s) 
  """  

	@connection_options nil
	use OpenAperture.Messaging

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    case GenServer.start_link(__MODULE__, %{}, name: __MODULE__) do
    	{:error, reason} -> 
        Logger.error("Failed to start OpenAperture Overseer:  #{inspect reason}")
        {:error, reason}
    	{:ok, pid} ->
        try do
          if Application.get_env(:autostart, :register_queues, false) do
        		case register_queues do
              {:ok, _} -> {:ok, pid}
              {:error, reason} -> 
                Logger.error("Failed to register Overseer queues:  #{inspect reason}")
                {:ok, pid}
            end    		
          else
            {:ok, pid}
          end
        rescue e in _ ->
          Logger.error("An error occurred registering Overseer queues:  #{inspect e}")
          {:ok, pid}
        end
    end
  end

  @doc """
  Method to register the Overseer queues with the Messaging system

  ## Return Value

  :ok | {:error, reason}
  """
  @spec register_queues() :: :ok | {:error, String.t()}
  def register_queues do
    Logger.debug("Registering Overseer queues...")
    workflow_orchestration_queue = QueueBuilder.build(ManagerApi.get_api, "overseer", Configuration.get_current_exchange_id)

    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
    subscribe(options, workflow_orchestration_queue, fn(payload, _meta, %{delivery_tag: delivery_tag} = async_info) -> 
      MessageManager.track(async_info)
      process_request(payload, delivery_tag) 
    end)
  end

  @doc """
  Method to process an incoming request

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec process_request(Map, String.t()) :: term
  def process_request(_payload, delivery_tag) do
    Logger.debug("No action is required for message #{delivery_tag}")
    acknowledge(delivery_tag)
  end

  @doc """
  Method to acknowledge a message has been processed

  ## Options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec acknowledge(String.t()) :: term
  def acknowledge(delivery_tag) do
    message = MessageManager.remove(delivery_tag)
    unless message == nil do
      SubscriptionHandler.acknowledge(message[:subscription_handler], message[:delivery_tag])
    end
  end

  @doc """
  Method to reject a message has been processed

  ## Options

  The `delivery_tag` option is the unique identifier of the message

  The `redeliver` option can be used to requeue a message
  """
  @spec reject(String.t(), term) :: term
  def reject(delivery_tag, redeliver \\ false) do
    message = MessageManager.remove(delivery_tag)
    unless message == nil do
      SubscriptionHandler.reject(message[:subscription_handler], message[:delivery_tag], redeliver)
    end
  end  
end