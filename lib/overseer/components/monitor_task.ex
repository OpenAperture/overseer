require Logger
require Timex.Date

defmodule OpenAperture.Overseer.Components.MonitorTask do

  alias OpenAperture.Overseer.Components.MonitorTask
  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.Workflow

  @logprefix "[Components][MonitorTask]"

  @moduledoc """
  This module contains the Task for Monitoring an in-progress upgrade
  """

  @doc """
  Method to start a new MonitorTask

  ## Option Values

  The `mgr` option defines the ComponentMgr PID

  ## Return Values

  Task
  """
  @spec create(pid) :: task
  def create(mgr) do
    Task.async(fn ->
      try do
        ComponentMgr.set_task(mgr, :monitoring_task, self)

        #wait a minute before doing any checks
        :timer.sleep(60000)
        execute_monitoring(mgr)
      catch
        :exit, code   ->
          component = ComponentMgr.refresh(mgr)
          Logger.error("#{@logprefix}[#{component["type"]}] Monitoring component #{component["id"]} Exited with code #{inspect code}")
          ComponentMgr.set_task(mgr, :monitoring_task, nil)
        :throw, value ->
          component = ComponentMgr.refresh(mgr)
          Logger.error("#{@logprefix}[#{component["type"]}] Monitoring component #{component["id"]} Throw called with #{inspect value}")
          ComponentMgr.set_task(mgr, :monitoring_task, nil)
        what, value   ->
          component = ComponentMgr.refresh(mgr)
          Logger.error("#{@logprefix}[#{component["type"]}] Monitoring component #{component["id"]} Caught #{inspect what} with #{inspect value}")
          ComponentMgr.set_task(mgr, :monitoring_task, nil)
      end
    end)
  end

  @doc """
  Method to execute Monitoring of a SystemComponent upgrade

  ## Option Values

  The `mgr` option defines the ComponentMgr PID

  """
  @spec execute_monitoring(pid) :: term
  def execute_monitoring(mgr) do
    component = ComponentMgr.refresh(mgr)
    if component["status"] != "upgrade_in_progress" do
      Logger.info("#{@logprefix}[#{component["type"]}] Component #{component["type"]} (#{component["id"]}) is not being upgraded (status is #{component["status"]}),  monitoring complete.")
    else
      case check_upgrade_status(mgr, component) do
        {:ok, :upgrade_completed} ->
          Logger.info("#{@logprefix}[#{component["type"]}] Upgrade monitoring task for type #{component["type"]} (#{component["id"]}) has completed in status :upgrade_completed")

          #save status
          upgrade_status = component["upgrade_status"]
          upgrade_status = Map.put(upgrade_status, "current_workflow", nil)

          component = Map.put(component, "source_repo", upgrade_status["target_source_repo"])
          component = Map.put(component, "source_repo_git_ref", upgrade_status["target_source_repo_git_ref"])
          component = Map.put(component, "deployment_repo", upgrade_status["target_deployment_repo"])
          component = Map.put(component, "deployment_repo_git_ref", upgrade_status["target_deployment_repo_git_ref"])

          component = Map.put(component, "status", "upgrade_completed")
          component = Map.put(component, "upgrade_status", nil)
          component = ComponentMgr.save(mgr, component)
        {:ok, status, current_workflow_id} ->
          Logger.info("#{@logprefix}[#{component["type"]}] Upgrade monitoring task for type #{component["type"]} (#{component["id"]}) is in status #{status}")

          #save status
          upgrade_status = component["upgrade_status"]
          upgrade_status = Map.put(upgrade_status, "current_workflow", current_workflow_id)
          component = Map.put(component, "upgrade_status", upgrade_status)
          component = Map.put(component, "status", status)

          ComponentMgr.save(mgr, component)
        {:error, reason} ->
          Logger.error("#{@logprefix}[#{component["type"]}] Upgrade monitoring task for type #{component["type"]} (#{component["id"]}) has failed: #{inspect reason}")

          #save failure
          upgrade_status = component["upgrade_status"]
          upgrade_status = Map.put(upgrade_status, "failure_reason", "Upgrade monitoring task for type #{component["type"]} (#{component["id"]}) has failed: #{inspect reason}")

          component = Map.put(component, "status", "upgrade_failed")
          component = Map.put(component, "upgrade_status", upgrade_status)
          ComponentMgr.save(mgr, component)
          ComponentMgr.set_task(mgr, :monitoring_task, nil)
      end
    end
  end

  @doc """
  Method to determine the correct status of the upgrade and take any necessary action, based on that status

  ## Option Values

  The `mgr` option defines the ComponentMgr PID

  ## Return Value

  {:ok, updated_status} | {:error, reason}

  """
  @spec check_upgrade_status(pid, map) :: {:ok, term} | {:error, term}
  def check_upgrade_status(mgr, component) do
    current_workflow = resolve_current_workflow(component["upgrade_status"])

    cond do
      #bad upgrade request
      current_workflow == nil ->
        {:error, "Invalid upgrade_status - no current workflow could be identified!"}

      #not started
      !current_workflow["workflow_completed"] && current_workflow["current_step"] == nil && current_workflow["elapsed_step_time"] == nil ->
        #execute the workflow
        execute_options = %{
        }
        case Workflow.execute_workflow!(ManagerApi.get_api, current_workflow["id"], execute_options) do
          false -> {:error, "Failed to execute the next Workflow - #{current_workflow["id"]}!"}
          true ->
            Logger.debug("#{@logprefix}[#{component["type"]}] Successfully executed the next Workflow - #{current_workflow["id"]}")

            #create another monitoring task
            MonitorTask.create(mgr)
            {:ok, :upgrade_in_progress, current_workflow["id"]}
        end
      #in-progress
      !current_workflow["workflow_completed"] ->
        #create another monitoring task
        MonitorTask.create(mgr)
        {:ok, :upgrade_in_progress, current_workflow["id"]}

      #completed in error
      current_workflow["workflow_error"] ->
        {:error, "Upgrade has failed - Workflow #{current_workflow["id"]} has failed!"}

      #finished all workflows successfully
      !current_workflow["workflow_error"] ->
        Logger.info("#{@logprefix}[#{component["type"]}] All upgrade workflows have completed successfully.")
        ComponentMgr.set_task(mgr, :monitoring_task, nil)
        {:ok, :upgrade_completed}
    end
  end

  @doc """
  Method to identify the currently executing (or last executed) Workflow

  ## Option Values

  The `upgrade_status` option defines the Map containing the upgrade status

  ## Return Value

  Map of the last Upgrade
  """
  @spec resolve_current_workflow(map) :: map
  def resolve_current_workflow(upgrade_status) do
    if upgrade_status == nil || upgrade_status["workflows"] == nil || length(upgrade_status["workflows"]) == 0 do
      nil
    else
      try do
        Enum.reduce upgrade_status["workflows"], nil, fn workflow_id, current_workflow ->
          workflow = Workflow.get_workflow!(ManagerApi.get_api, workflow_id)

          cond do
            workflow == nil -> raise "An error occurred retrieving Workflow #{workflow_id}!"
            workflow["workflow_error"] -> workflow
            current_workflow == nil -> workflow
            current_workflow["workflow_completed"] == true && current_workflow["workflow_error"] == false -> workflow
            true -> current_workflow
          end
        end
      rescue e in _ ->
        Logger.error("#{@logprefix} An error occurred monitoring Upgrade:  #{inspect e}")
        nil
      end
    end
  end
end
