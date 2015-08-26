require Logger
require Timex.Date

defmodule OpenAperture.Overseer.Components.ComponentStatusMgr do
  use GenServer
  use Timex

  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.Overseer.Components.MonitorTask

  @logprefix "[Components][ComponentStatusMgr]"

  @moduledoc """
  This module contains the GenServer for a checking if upgrades need to be created
  """

  @doc """
  Specific start_link implementation

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(pid) :: {:ok, pid} | {:error, String.t}
  def start_link(mgr) do
    case GenServer.start_link(__MODULE__, %{component_mgr: mgr}) do
      {:error, reason} -> {:error, reason}
      {:ok, mgr} ->
        GenServer.cast(mgr, {:check_for_upgrade})
        {:ok, mgr}
    end
  end

  @doc """
  GenServer callback to check for upgrades for a SystemComponent

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

      {:noreply, state}
  """
  @spec handle_cast({:check_for_upgrade}, map) :: {:noreply, map}
  def handle_cast({:check_for_upgrade}, state) do
    check_for_upgrade(state)

    GenServer.cast(self, {:check_for_upgrade})
    {:noreply, state}
  end

  @doc """
  Method to check for upgrades for a SystemComponent

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

  state
  """
  @spec check_for_upgrade(map) :: map
  def check_for_upgrade(state) do
    component = ComponentMgr.component(state[:component_mgr])
    upgrade_strategy = if component["upgrade_strategy"] != nil, do: String.to_atom(component["upgrade_strategy"])
    type = component["type"]

    cond do
      ComponentMgr.current_upgrade_task(state[:component_mgr]) != nil ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Component #{type} is currently being upgraded")
        #after 5 minutes, request another upgrade check (ensure the definition hasn't changed)
        :timer.sleep(300000)
      component["status"] == "upgrade_in_progress" ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Component #{type} is not currently being monitored, but an upgrade is in progress.  Requesting a MonitorTask...")
        #the component is being upgraded, ensure that we have some task running.  If not, start a Monitoring task
        #to resolve the current state
        MonitorTask.create(state[:component_mgr])
        #after 5 minutes, request another upgrade check (ensure the definition hasn't changed)
        :timer.sleep(300000)
      true ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Component #{type} is not currently being monitored, reviewing for upgrade...")

        execute_upgrade = cond do
          upgrade_strategy == :hourly ->
            Logger.debug("#{@logprefix}[#{component["type"]}] An hourly upgrade strategy has been defined for component #{type}")

            #pick a time randomly <= 1 hour
            :timer.sleep(:random.uniform(3600000))
            true
          true ->
            Logger.debug("#{@logprefix}[#{component["type"]}] A manual upgrade strategy has been defined for component #{type}")

            #after 5 minutes, request another upgrade check (ensure the definition hasn't changed)
            :timer.sleep(300000)
            false
        end

        if execute_upgrade, do: ComponentMgr.request_upgrade(state[:component_mgr])
    end
  end
end


