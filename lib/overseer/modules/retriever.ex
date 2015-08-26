require Logger

defmodule OpenAperture.Overseer.Modules.Retriever do
  use GenServer

  @moduledoc """
  This module contains the GenServer for retrieving and caching MessagingExchangeModules
  """

  alias OpenAperture.ManagerApi.MessagingExchangeModule
  alias OpenAperture.Overseer.Modules.Manager
  alias OpenAperture.Overseer.Configuration

  ## Consumer Methods

  @doc """
  Specific start_link implementation

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t}
  def start_link() do
    case GenServer.start_link(__MODULE__, [], name: __MODULE__) do
      {:ok, retriever} ->
				if Application.get_env(:autostart, :retrieve_modules, true) do
      		GenServer.cast(retriever, {:retrieve_module_list})
    		end

       	{:ok, retriever}
      {:error, reason} -> {:error, "[Retriever] Failed to create Modules.Manager: #{inspect reason}"}
    end
  end

  @doc """
  GenServer callback for handling the :retrieve_module_list event.  This method
  will retrieve MessagingExchangeModules for the configured messaging exchange.

      {:noreply, new modules list}
  """
  @spec handle_cast({:retrieve_module_list}, term) :: {:noreply, list}
  def handle_cast({:retrieve_module_list}, _state) do
    modules = refresh_modules

    sleep_seconds = :random.uniform(300)
    if sleep_seconds < 60 do
      sleep_seconds = 60
    end
    Logger.debug("[Retriever] Sleeping for #{sleep_seconds} seconds before retrieving system modules...")
    :timer.sleep(sleep_seconds * 1000)
    GenServer.cast(__MODULE__, {:retrieve_module_list})

    {:noreply, modules}
  end

  def refresh_modules do
    exchange_id = Configuration.get_current_exchange_id
    Logger.debug("[Retriever] Retrieving system modules for exchange #{exchange_id}...")

    modules = case MessagingExchangeModule.list!(exchange_id) do
      nil ->
        Logger.error("[Retriever] Unable to load system modules from exchange #{exchange_id}!")
        nil
      modules -> modules
    end
    Manager.set_modules(modules)

    modules
  end
end
