require Logger

defmodule OpenAperture.Overseer.Components.ComponentsMgr do
	use GenServer

  alias OpenAperture.Overseer.Configuration
  alias OpenAperture.Overseer.Components.ComponentMgr

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange

  @logprefix "[Components][ComponentsMgr]"

  @moduledoc """
  This module contains the GenServer for managing SystemComponents associated with the configured Exchange
  """  

  @doc """
  Specific start_link implementation

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}  
  def start_link() do
    Logger.debug("#{@logprefix} Starting...")

    case Agent.start_link(fn -> %{} end, name: :ComponentMgrStore) do
      {:error, reason} -> {:error, reason}
      {:ok, _} ->
        case GenServer.start_link(__MODULE__, %{managers: %{}}, name: __MODULE__) do
          {:ok, pid} ->
            if Application.get_env(:autostart, :component_mgr, true) do
              GenServer.cast(pid, {:resolve_system_components})
            end

            {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Method to retrieve the manager for a specific SystemComponent type

  ## Optiona Value

  The `type` option defines the SystemComponent type

  ## Return Value

  ComponentMgr pid
  """
  @spec get_mgr_for_component_type(String.t) :: pid
  def get_mgr_for_component_type(type) do
    Agent.get(:ComponentMgrStore, fn store -> store end)[type]
  end

  @doc """
  GenServer callback for handling the :resolve_system_components event.  This method
  will retrieve the assigned component list every 5 minutes

  {:noreply, state}
  """
  @spec handle_cast({:resolve_system_components}, Map) :: {:noreply, Map}
  def handle_cast({:resolve_system_components}, state) do
    state = resolve_system_components(state)
    :timer.sleep(300000)
    GenServer.cast(__MODULE__, {:resolve_system_components})
    {:noreply, state}
  end

  @doc """
  Method for ensuring that a ComponentMgr exists for each type of Component assigned to 
  the current exchange

  ## Options

  The `state` option contains the GenServer's state

  ## Return Value

  Map, containing the updated state
  """
  @spec resolve_system_components(Map) :: Map
  def resolve_system_components(state) do
    exchange_id = Configuration.get_current_exchange_id

    components = MessagingExchange.exchange_components!(ManagerApi.get_api, exchange_id)
    if components == nil || length(components) == 0 do
      Logger.debug("#{@logprefix} No components are assigned to exchange #{exchange_id}")
      updated_state = state
    else
      Logger.debug("#{@logprefix} There are #{length(components)} component(s) assigned to exchange #{exchange_id}")

      #spin through the components
      {updated_state, remaining_managers} = Enum.reduce components, {state, Map.keys(state[:managers])}, fn component, {updated_state, remaining_managers} ->
        if updated_state[:managers][component["type"]] == nil do
          Logger.debug("#{@logprefix} There are #{length(components)} component(s) assigned to exchange #{exchange_id}")
          case ComponentMgr.start_link(component) do
            {:error, reason} -> 
              Logger.error("#{@logprefix} Failed to start a ComponentMgr for component #{component["type"]} (#{component["id"]}):  #{inspect reason}")
            {:ok, mgr} ->
              managers = Map.put(updated_state[:managers], component["type"], mgr)
              updated_state = Map.put(updated_state, :managers, managers)
              Agent.update(:ComponentMgrStore, fn _ -> managers end)
          end
        else
          Logger.debug("#{@logprefix} A manager already exists for Component #{component["type"]} (#{component["id"]})")
        end

        {updated_state, List.delete(remaining_managers, component["type"])}
      end

      #stop any managers for components that are no longer assigned
      if length(remaining_managers) > 0 do
        updated_state = Enum.reduce remaining_managers, updated_state, fn manager, remaining_managers ->
          type = ComponentMgr.component(manager)["type"]
          Process.exit(manager, :normal)
          Map.delete(remaining_managers, type)
        end

        Agent.update(:ComponentMgrStore, fn _ -> updated_state[:managers] end)
      end
    end

    updated_state
  end
end