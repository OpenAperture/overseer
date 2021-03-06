require Logger
require Timex.Date

defmodule OpenAperture.Overseer.Components.ComponentMgr do
	use GenServer
  use Timex

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemComponent

  alias OpenAperture.Overseer.Components.ComponentStatusMgr
  alias OpenAperture.Overseer.Components.UpgradeTask
  alias OpenAperture.Overseer.Components.MonitorTask

  @logprefix "[Components][ComponentMgr]"

  @moduledoc """
  This module contains the GenServer for managing a specific SystemComponent and kicking off upgrades as needed
  """

  @doc """
  Specific start_link implementation

  ## Option Values

  The `component` option defines the SystemComponent map to be managed

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(map) :: {:ok, pid} | {:error, String.t}
  def start_link(component) do
    Logger.debug("#{@logprefix}[#{component["type"]}] Starting...")
    case GenServer.start_link(__MODULE__, %{component: component, updated_at: Time.now()}) do
      {:error, reason} -> {:error, reason}
      {:ok, mgr} ->
        case ComponentStatusMgr.start_link(mgr) do
          {:error, reason} -> {:error, reason}
          {:ok, status_mgr} ->
            GenServer.call(mgr, {:set_status_mgr, status_mgr})

            #if the Overseer gets restarted as a result of an upgrade, we need to restart the monitoring task
            if component["status"] == "upgrade_in_progress" do
              Logger.debug("#{@logprefix}[#{component["type"]}] An upgrade is in-progress, creating a Monitoring task...")
              task = MonitorTask.create(mgr)
              set_task(mgr, :monitoring_task, task)
            end
            {:ok, mgr}
        end
    end
  end

  @doc """
  Method to refresh the currently managed SystemComponent

  ## Option Values

  The `mgr` option is the GenServer PID

  ## Return Values

  Map containing the refreshed component
  """
  @spec refresh(pid) :: map
  def refresh(mgr) do
    GenServer.call(mgr, {:refresh_component})
  end

  @doc """
  Method to retrieve the currently managed SystemComponent

  ## Option Values

  The `mgr` option is the GenServer PID

  ## Return Values

  Map containing the cached component
  """
  @spec component(pid) :: map
  def component(mgr) do
    GenServer.call(mgr, {:get_component})
  end

  @doc """
  Method to save a new version of the currently managed SystemComponent

  ## Option Values

  The `mgr` option is the GenServer PID

  The `updated_component` option defines the component to update

  ## Return Values

  Map containing the updated component
  """
  @spec save(pid, map) :: map
  def save(mgr, updated_component) do
    GenServer.call(mgr, {:save, updated_component})
  end

  @doc """
  Method to request an Upgrade of the component

  ## Option Values

  The `mgr` option is the GenServer PID

  ## Return Values

  the upgrade / monitoring async Task
  """
  @spec request_upgrade(pid) :: Task.t
  def request_upgrade(mgr) do
    GenServer.call(mgr, {:request_upgrade})
  end

  @doc """
  Method to get the current upgrade/monitor Task

  ## Option Values

  The `mgr` option is the GenServer PID

  ## Return Values

  the upgrade / monitoring async Task
  """
  @spec current_upgrade_task(pid) :: Task.t
  def current_upgrade_task(mgr) do
    GenServer.call(mgr, {:current_upgrade_task})
  end

  @doc """
  Method to set the upgrade or monitoring task associated with the SystemComponent

  ## Option Values

  The `mgr` option is the GenServer PID

  ## Return Values

  the upgrade / monitoring async Task
  """
  @spec set_task(pid, term, Task.t) :: Task.t
  def set_task(mgr, task_type, task) do
    GenServer.call(mgr, {:set_upgrade_task, task_type, task})
  end

  @doc """
  GenServer callback to retrieve the currently managed SystemComponent

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  ## Return Values

  {:reply, component, state}
  """
  @spec handle_call({:get_component}, pid, map) :: {:reply, map, map}
  def handle_call({:get_component}, _from, state) do
    {:reply, state[:component], state}
  end

  @doc """
  GenServer callback to update and save the managed SystemComponent

  ## Option Values

  The `updated_component` option defines the new component

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  ## Return Values

  {:reply, updated_component or original if save fails, state}
  """
  @spec handle_call({:save, map}, pid, map) :: {:reply, map, map}
  def handle_call({:save, updated_component}, _from, state) do
    response = SystemComponent.update_system_component(ManagerApi.get_api, updated_component["id"], updated_component)
    if response.success? do
      Logger.debug("#{@logprefix}[#{updated_component["type"]}] Successfully saved updated_component #{updated_component["id"]}")
      state = Map.put(state, :component, updated_component)
      state = Map.put(state, :updated_at, Time.now())
      {:reply, updated_component, state}
    else
      Logger.error("#{@logprefix}[#{updated_component["type"]}] Failed to save updated_component #{updated_component["id"]}:  #{inspect response}")
      {:reply, state[:component], state}
    end
  end

  @doc """
  GenServer callback to refresh the currently managed SystemComponent

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  ## Return Values

  {:reply, updated component, state}
  """
  @spec handle_call({:refresh_component}, pid, map) :: {:reply, map, map}
  def handle_call({:refresh_component}, _from, state) do
    case SystemComponent.get_system_component!(ManagerApi.get_api, state[:component]["id"]) do
      nil ->
        Logger.error("#{@logprefix}[#{state[:component]["type"]}] Failed to refresh component #{state[:component]["id"]}!")
      component ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Successfully refreshed component #{component["id"]}")
        state = Map.put(state, :component, component)
        state = Map.put(state, :updated_at, Time.now())
    end

    {:reply, state[:component], state}
  end

  @doc """
  GenServer callback to refresh the currently managed SystemComponent

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  ## Return Values

  {:reply, Task, state}
  """
  @spec handle_call({:request_upgrade}, pid, map) :: {:reply, Task.t, map}
  def handle_call({:request_upgrade}, _from, state) do

    if state[:upgrade_task] != nil && (state[:upgrade_task].pid == nil || !Process.alive?(state[:upgrade_task].pid)) do
      Logger.debug("#{@logprefix}[#{state[:component]["type"]}] A zombie UpgradeTask has been found for #{state[:component]["id"]}; clearing saved UpgradeTask")
      state = Map.put(state, :upgrade_task, nil)
    end

    if state[:monitoring_task] != nil && (state[:monitoring_task].pid == nil || !Process.alive?(state[:monitoring_task].pid)) do
      Logger.debug("#{@logprefix}[#{state[:component]["type"]}] A zombie MonitoringTask has been found for #{state[:component]["id"]}; clearing saved MonitoringTask")
      state = Map.put(state, :monitoring_task, nil)
    end

    task = cond do
      state[:monitoring_task] != nil ->
        Logger.debug("#{@logprefix}[#{state[:component]["type"]}] An upgrade has been requested for component #{state[:component]["id"]}; upgrade is currently being monitored.")
        state[:monitoring_task]
      state[:upgrade_task] != nil ->
        Logger.debug("#{@logprefix}[#{state[:component]["type"]}] An upgrade has been requested for component #{state[:component]["id"]}; upgrade is currently in-progress.")
        state[:upgrade_task]
      true ->
        Logger.debug("#{@logprefix}[#{state[:component]["type"]}] An upgrade has been requested for component #{state[:component]["id"]}; a new upgrade has been requested")
        UpgradeTask.create(self)
    end

    {:reply, task, state}
  end

  @doc """
  GenServer callback to retrieve the currently executing task

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  ## Return Values

  {:reply, task, state}
  """
  @spec handle_call({:current_upgrade_task}, pid, map) :: {:reply, Task.t, map}
  def handle_call({:current_upgrade_task}, _from, state) do
    task = cond do
      state[:monitoring_task] != nil -> state[:monitoring_task]
      state[:upgrade_task] != nil -> state[:upgrade_task]
      true -> nil
    end

    {:reply, task, state}
  end

  @doc """
  GenServer callback to set the current status manager

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  The `mgr` option defines the status manager to save

  ## Return Values

      {:reply, manager, state}
  """
  @spec handle_call({:set_status_mgr, pid}, pid, map) :: {:reply, pid, map}
  def handle_call({:set_status_mgr, mgr}, _from, state) do
    state = Map.put(state, :status_mgr, mgr)
    {:reply, mgr, state}
  end

  @doc """
  GenServer callback to set the current status manager

  ## Option Values

  The `_from` option is the caller's PID

  The `state` option is the GenServer's state

  The `task_type` option defines the atom identifying what kind of task (:update_task, :monitoring_task)

  The `task` option defines the Task

  ## Return Values

      {:reply, manager, state}
  """
  @spec handle_call({:set_upgrade_task, term, Task.t}, pid, map) :: {:reply, Task.t, map}
  def handle_call({:set_upgrade_task, task_type, task}, _from, state) do
    state = Map.put(state, task_type, task)
    {:reply, task, state}
  end
end
