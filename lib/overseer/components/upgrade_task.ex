require Logger
require Timex.Date

defmodule OpenAperture.Overseer.Components.UpgradeTask do

  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.Overseer.Components.MonitorTask

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.Workflow
  alias OpenAperture.ManagerApi.SystemComponentRef

  @logprefix "[Components][UpgradeTask]"

  @moduledoc """
  This module contains the Task for executing an upgrade
  """  

  @doc """
  Method to start a new UpgradeTask

  ## Option Values

  The `mgr` option defines the ComponentMgr PID

  ## Return Values

  Task
  """
  @spec create(pid) :: Task
	def create(mgr) do
    Task.async(fn -> 
      try do
        ComponentMgr.set_task(mgr, :upgrade_task, self)
        execute_upgrade(mgr)
      after
        ComponentMgr.set_task(mgr, :upgrade_task, nil)
      end
    end)
  end

  @doc """
  Method to determine if an upgrade is possible and, if so, execute it

  ## Option Values

  The `mgr` option defines the ComponentMgr PID
  """
  @spec execute_upgrade(pid) :: term
  def execute_upgrade(mgr) do
    #refresh to make sure that nothing has changed
    component = ComponentMgr.refresh(mgr)
    type = component["type"]

    Logger.debug("#{@logprefix}[#{component["type"]}] An upgrade has been request for component #{type}, ensuring eligibility...")
    case eligible_for_upgrade?(component) do
      {false, reason, ref_component} ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Component #{type} is not eligible for upgrade:  #{inspect reason}")
        component = ComponentMgr.component(mgr)
        upgrade_status = component["upgrade_status"]
        if upgrade_status == nil, do: upgrade_status = %{}
        upgrade_status = Map.put(upgrade_status, "failure_reason", "Component #{type} is not eligible for upgrade:  #{inspect reason}")
        component = Map.put(component, "status", "ineligible_for_upgrade")
        component = Map.put(component, "upgrade_status", upgrade_status)

        if ref_component != nil do
          component = Map.put(component, "source_repo", ref_component["source_repo"])
          component = Map.put(component, "source_repo_git_ref", ref_component["source_repo_git_ref"])
        end

        ComponentMgr.save(mgr, component)
      {true, ref_component} ->
        Logger.debug("#{@logprefix}[#{component["type"]}] Component #{type} is eligible for upgrade")
        case upgrade(mgr, component, ref_component) do
          :ok -> 
            #create a monitoring task
            Logger.debug("#{@logprefix}[#{component["type"]}] The upgrade has started successfully, creating a MonitoringTask...")
            MonitorTask.create(mgr)
            Logger.debug("#{@logprefix}[#{component["type"]}] Upgrade task has completed")
          {:error, reason} ->
            component = ComponentMgr.component(mgr)
            upgrade_status = component["upgrade_status"]
            if upgrade_status == nil, do: upgrade_status = %{}
            upgrade_status = Map.put(upgrade_status, "failure_reason", "Upgrade monitoring task for type #{component["type"]} (#{component["id"]}) has failed: #{inspect reason}")

            component = Map.put(component, "status", "upgrade_failed")
            component = Map.put(component, "upgrade_status", upgrade_status)
            ComponentMgr.save(mgr, component)
            Logger.debug("#{@logprefix}[#{component["type"]}] Upgrade task has completed")      
        end
    end
  end

  @doc """
  Method to determine if a SystemComponent and SystemComponentRef are currently eligible to be upgraded

  ## Option Values

  The `component` option defines the Map of the SystemComponent

  ## Return Value

  {true, SystemComponentRef} | {false, reason, SystemComponentRef}
  """
  @spec eligible_for_upgrade?(Map) :: {true, Map} | {false, term, Map}
  def eligible_for_upgrade?(component) do
    type = component["type"]
    case SystemComponentRef.get_system_component_ref!(ManagerApi.get_api, type) do
      nil -> {false, "An error occurred retrieving SystemComponentRef for type #{type}!", nil}
      ref_component ->
        cond do
          component["status"] == "upgrade_in_progress" ->
            {false, "An upgrade is already in progress for component #{component["type"]}", ref_component}
          component["upgrade_strategy"] == nil || component["upgrade_strategy"] == "manual" ->
            {false, "The defined upgrade strategy for component #{component["type"]} is not automatic:  #{inspect component["upgrade_strategy"]}", ref_component}
          component["deployment_repo"] == nil || String.length(component["deployment_repo"]) == 0 ->
            {false, "deployment_repo for SystemComponent of type #{type} is invalid.  No upgrade will occur.", ref_component}
          component["deployment_repo_git_ref"] == nil || String.length(component["deployment_repo_git_ref"]) == 0 ->
            {false, "deployment_repo_git_ref for SystemComponent of type #{type} is invalid.  No upgrade will occur.", ref_component}
          ref_component["auto_upgrade_enabled"] != true ->
            {false, "Automatic upgrades for SystemComponentRef of type #{type} has been disabled.  No upgrade will occur.", ref_component}
          ref_component["source_repo"] == nil || String.length(ref_component["source_repo"]) == 0 ->
            {false, "source_repo for SystemComponentRef of type #{type} is invalid.  No upgrade will occur.", ref_component}
          ref_component["source_repo_git_ref"] == nil || String.length(ref_component["source_repo_git_ref"]) == 0 ->
            {false, "source_repo_git_ref for SystemComponentRef of type #{type} is invalid.  No upgrade will occur.", ref_component}
          #check if any of the values are different, if so we need to upgrade
          ref_component["source_repo"] != component["source_repo"] ||
          ref_component["source_repo_git_ref"] != component["source_repo_git_ref"] -> {true, ref_component}
          true -> {false, "SystemComponent #{component["type"]} is already running the latest.  No upgrade will occur.", ref_component}
        end
    end
  end

  @doc """
  Method to determine if a SystemComponentRef is currently eligible to be upgraded

  ## Option Values

  The `mgr` option defines the ComponentMgr

  The `component` option defines the Map of the SystemComponent

  The `ref_component` option defines the Map of the SystemComponentRef

  ## Return Value

  :ok | {:error, reason}
  """
  @spec upgrade(pid, Map, Map) :: :ok | {:error, term}
  def upgrade(mgr, component, ref_component) do
    Logger.debug("#{@logprefix}[#{component["type"]}] Component #{component["type"]} is eligible for upgrade, executing an upgrade request...")

    case create_upgrade_workflows(component, ref_component) do
      {:error, reason} -> {:error, reason}
      {:ok, workflows} ->
        #update component status to upgrade_in_progress with ID, including fields from ref
        upgrade_status = component["upgrade_status"]
        if upgrade_status == nil do
          upgrade_status = %{}
        end

        first_workflow_id = List.first(workflows)

        upgrade_status = Map.put(upgrade_status, "workflows", workflows)
        upgrade_status = Map.put(upgrade_status, "current_workflow", first_workflow_id)
        upgrade_status = Map.put(upgrade_status, "upgrade_start_time", "#{:httpd_util.rfc1123_date(:calendar.universal_time())}")
        upgrade_status = Map.put(upgrade_status, "failure_reason", "")
        upgrade_status = Map.put(upgrade_status, "target_source_repo", ref_component["source_repo"])
        upgrade_status = Map.put(upgrade_status, "target_source_repo_git_ref", ref_component["source_repo_git_ref"])
        upgrade_status = Map.put(upgrade_status, "target_deployment_repo", component["deployment_repo"])
        upgrade_status = Map.put(upgrade_status, "target_deployment_repo_git_ref", component["deployment_repo_git_ref"])

        component = Map.put(component, "status", "upgrade_in_progress")
        component = Map.put(component, "upgrade_status", upgrade_status)

        #save here so no other Overseer starts the upgrade
        component = ComponentMgr.save(mgr, component)

        
        #execute first workflow
        execute_options = %{
        }
        case Workflow.execute_workflow!(ManagerApi.get_api, first_workflow_id, execute_options) do
          false -> {:error, "Failed to execute workflow #{first_workflow_id}!"}
          true ->
            Logger.debug("#{@logprefix}[#{component["type"]}] Successfully executed Workflow #{first_workflow_id}")
            :ok
        end
    end
  end

  @doc """
  Method to create the required Workflows for the ugprade

  ## Option Values

  The `component` option defines the Map of the SystemComponent

  The `ref_component` option defines the Map of the SystemComponentRef

  ## Return Value

  {:ok, Workflows} | {:error, reason}
  """
  @spec create_upgrade_workflows(Map, Map) :: {:ok, List} | {:error, term}
  def create_upgrade_workflows(component, ref_component) do
    workflow_request = %{
      deployment_repo: component["deployment_repo"],
      deployment_repo_git_ref: component["deployment_repo_git_ref"],
      source_repo: ref_component["source_repo"],
      source_repo_git_ref: ref_component["source_repo_git_ref"],
      milestones: [:config, :deploy_oa] #note that setting :deploy_oa will use the OA Deployer to cycle services
    }

    case Workflow.create_workflow!(ManagerApi.get_api, workflow_request) do
      nil -> {:error, "Failed to create Workflow for request #{inspect workflow_request}"}
      workflow_request_id ->
        workflows = [workflow_request_id]
        
        if ref_component["type"] == "deployer" do
          workflow_request = %{
            deployment_repo: "#{component["deployment_repo"]}_oa",
            deployment_repo_git_ref: component["deployment_repo_git_ref"],
            source_repo: ref_component["source_repo"],
            source_repo_git_ref: ref_component["source_repo_git_ref"],
            milestones: [:config, :deploy] #note that setting :deploy will user the Deployer to cycle services
          }

          case Workflow.create_workflow!(ManagerApi.get_api, workflow_request) do
            nil -> {:error, "Failed to create Workflow for request #{inspect workflow_request}"}
            workflow_request_id -> {:ok, workflows ++ [workflow_request_id]}
          end
        else
          {:ok, workflows}
        end
    end
  end
end