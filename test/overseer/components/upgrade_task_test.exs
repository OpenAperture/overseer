defmodule OpenAperture.Overseer.Components.UpgradeTaskTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Components.MonitorTask
  alias OpenAperture.Overseer.Components.UpgradeTask

  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.Overseer.Components.ComponentStatusMgr
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemComponent
  alias OpenAperture.ManagerApi.Workflow
  alias OpenAperture.ManagerApi.SystemComponentRef
  
  # ===================================
  # create_upgrade_workflows tests

  test "create_upgrade_workflows - non-deployer" do
    workflow_uuid = "#{UUID.uuid1()}"
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,_ -> workflow_uuid end)

    ref_component = %{
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master",
    }

    component = %{
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    assert UpgradeTask.create_upgrade_workflows(component, ref_component) == {:ok, [workflow_uuid]}
  after
    :meck.unload(Workflow)
  end

  test "create_upgrade_workflows - deployer" do
    workflow_uuid = "#{UUID.uuid1()}"
    workflow_uuid2 = "#{UUID.uuid1()}"

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,request -> 
      if String.contains?(request[:deployment_repo], "_oa") do
        workflow_uuid2
      else
        workflow_uuid 
      end
    end)

    ref_component = %{
      "type" => "deployer",
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master",
    }

    component = %{
      "type" => "deployer",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    {:ok, workflows} = UpgradeTask.create_upgrade_workflows(component, ref_component)
    assert length(workflows) == 2
    assert List.first(workflows) == workflow_uuid
    assert List.last(workflows) == workflow_uuid2
  after
    :meck.unload(Workflow)
  end

  # ===================================
  # upgrade tests

  test "upgrade - create_upgrade_workflows fails" do
    workflow_uuid = "#{UUID.uuid1()}"
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,_ -> nil end)

    ref_component = %{
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master",
    }

    component = %{
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)

    {result, status} = UpgradeTask.upgrade(mgr, component, ref_component)
    assert result == :error
    assert status != nil
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end

  test "upgrade - execute_workflow fails" do
    workflow_uuid = "#{UUID.uuid1()}"
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,_ -> workflow_uuid end)
    :meck.expect(Workflow, :execute_workflow!, fn _,_,_ -> false end)

    ref_component = %{
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master",
    }

    component = %{
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)

    {result, status} = UpgradeTask.upgrade(mgr, component, ref_component)
    assert result == :error
    assert status != nil
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end

  test "upgrade - success" do
    workflow_uuid = "#{UUID.uuid1()}"
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,_ -> workflow_uuid end)
    :meck.expect(Workflow, :execute_workflow!, fn _,_,_ -> true end)

    ref_component = %{
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master",
    }

    component = %{
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)

    assert UpgradeTask.upgrade(mgr, component, ref_component) == :ok
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end

  # ===================================
  # eligible_for_upgrade? tests

  test "eligible_for_upgrade? - get_system_component_ref! fails" do
    ref_component = %{
    }

    component = %{
      "type" => "test"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> nil end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "SystemComponentRef for type")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - status" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "upgrade_in_progress"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "An upgrade is already in progress")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - upgrade_strategy not set" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "not_started"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "defined upgrade strategy for component")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - upgrade_strategy manual" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "manual"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "The defined upgrade strategy for")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - missing deployment_repo" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "deployment_repo")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - missing deployment_repo_git_ref" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "deployment_repo_git_ref")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - auto_upgrade_enabled not set" do
    ref_component = %{
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "has been disabled")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - auto_upgrade_enabled false" do
    ref_component = %{
      "auto_upgrade_enabled" => false
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "has been disabled")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - missing source_repo" do
    ref_component = %{
      "auto_upgrade_enabled" => true
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "source_repo")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - missing source_repo_git_ref" do
    ref_component = %{
      "auto_upgrade_enabled" => true,
      "source_repo" => "http://github.com/OpenAperture/component"
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "source_repo_git_ref")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - same source info" do
    ref_component = %{
      "auto_upgrade_enabled" => true,
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master"
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master",
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, reason, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == false
    assert String.contains?(reason, "is already running the latest")
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - different source_repo_git_ref" do
    ref_component = %{
      "auto_upgrade_enabled" => true,
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master"
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master",
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "old"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == true
    assert returned_ref_component == ref_component
  after
    :meck.unload(SystemComponentRef)
  end

  test "eligible_for_upgrade? - different source_repo" do
    ref_component = %{
      "auto_upgrade_enabled" => true,
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master"
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master",
      "source_repo" => "http://github.com/OpenAperture/component2",
      "source_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {result, returned_ref_component} = UpgradeTask.eligible_for_upgrade?(component)
    assert result == true
    assert returned_ref_component == ref_component
  after
    :meck.unload(SystemComponentRef)
  end

  # ===================================
  # execute_upgrade tests

  test "execute_upgrade - not eligible" do
    ref_component = %{
    }

    component = %{
      "type" => "test"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> nil end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :refresh, fn _ -> component end)
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)

    UpgradeTask.execute_upgrade(mgr)
  after
    :meck.unload(SystemComponentRef)
    :meck.unload(ComponentMgr)
  end

  test "execute_upgrade - eligible" do
    workflow_uuid = "#{UUID.uuid1()}"
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_workflow!, fn _,_ -> workflow_uuid end)
    :meck.expect(Workflow, :execute_workflow!, fn _,_,_ -> true end)

    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> :ok end)

    ref_component = %{
      "auto_upgrade_enabled" => true,
      "source_repo" => "http://github.com/OpenAperture/component",
      "source_repo_git_ref" => "master"
    }

    component = %{
      "type" => "test",
      "status" => "not_started",
      "upgrade_strategy" => "hourly",
      "deployment_repo" => "http://github.com/OpenAperture/component_deploy",
      "deployment_repo_git_ref" => "master",
      "source_repo" => "http://github.com/OpenAperture/component2",
      "source_repo_git_ref" => "master"
    }

    :meck.new(SystemComponentRef, [:passthrough])
    :meck.expect(SystemComponentRef, :get_system_component_ref!, fn _,_ -> ref_component end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :refresh, fn _ -> component end)
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)

    UpgradeTask.execute_upgrade(mgr)
  after
    :meck.unload(SystemComponentRef)
    :meck.unload(ComponentMgr)
    :meck.unload(Workflow)
  end    
end