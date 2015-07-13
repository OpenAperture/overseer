defmodule OpenAperture.Overseer.Components.MonitorTaskTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Components.MonitorTask

  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.Overseer.Components.ComponentStatusMgr
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemComponent
  alias OpenAperture.ManagerApi.Workflow
  
  # ===================================
  # resolve_current_workflow tests

  test "resolve_current_workflow - invalid status" do
    assert MonitorTask.resolve_current_workflow(nil) == nil
  end

  test "resolve_current_workflow - invalid workflows" do
    upgrade_status = %{

    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == nil
  end

  test "resolve_current_workflow - no workflows" do
    upgrade_status = %{
      "workflows" => []
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == nil
  end

  test "resolve_current_workflow - workflow failed to load" do
    workflow_uuid = "#{UUID.uuid1()}" 
    upgrade_status = %{
      "workflows" => [workflow_uuid]
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _,incoming_workflow_id -> 
      assert incoming_workflow_id == workflow_uuid
      nil
    end)

    assert MonitorTask.resolve_current_workflow(upgrade_status) == nil
  after
    :meck.unload(Workflow)
  end  

  test "resolve_current_workflow - workflow in error" do
    workflow_uuid = "#{UUID.uuid1()}" 

    workflow = %{
      "id" => workflow_uuid,
      "workflow_completed" => true,
      "workflow_error" => true,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _,incoming_workflow_id -> 
      assert incoming_workflow_id == workflow_uuid
      workflow
    end)

    upgrade_status = %{
      "workflows" => [workflow_uuid]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow
  after
    :meck.unload(Workflow)
  end  

  test "resolve_current_workflow - second workflow in error" do
    workflow_error_uuid = "#{UUID.uuid1()}" 
    workflow_error = %{
      "id" => workflow_error_uuid,
      "workflow_completed" => true,
      "workflow_error" => true,
    }

    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _,incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_error_uuid -> workflow_error
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid, workflow_error_uuid]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_error
  after
    :meck.unload(Workflow)
  end 

  test "resolve_current_workflow - first workflow in error" do
    workflow_error_uuid = "#{UUID.uuid1()}" 
    workflow_error = %{
      "id" => workflow_error_uuid,
      "workflow_completed" => true,
      "workflow_error" => true,
    }

    workflow_in_progress_uuid = "#{UUID.uuid1()}" 
    workflow_in_progress = %{
      "id" => workflow_in_progress_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_error_uuid -> workflow_error
        incoming_workflow_id == workflow_in_progress_uuid -> workflow_in_progress
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_error_uuid, workflow_in_progress_uuid]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_error
  after
    :meck.unload(Workflow)
  end 

  test "resolve_current_workflow - first workflow in progress" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    workflow_in_progress_uuid = "#{UUID.uuid1()}" 
    workflow_in_progress = %{
      "id" => workflow_in_progress_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    workflow_in_progress_uuid2 = "#{UUID.uuid1()}" 
    workflow_in_progress2 = %{
      "id" => workflow_in_progress_uuid2,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_in_progress_uuid -> workflow_in_progress
        incoming_workflow_id == workflow_in_progress_uuid2 -> workflow_in_progress2
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_in_progress_uuid, workflow_in_progress_uuid2]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_in_progress
  after
    :meck.unload(Workflow)
  end 

  test "resolve_current_workflow - first workflow completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    workflow_in_progress_uuid = "#{UUID.uuid1()}" 
    workflow_in_progress = %{
      "id" => workflow_in_progress_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_in_progress_uuid -> workflow_in_progress
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid, workflow_in_progress_uuid]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_in_progress
  after
    :meck.unload(Workflow)
  end 

  test "resolve_current_workflow - all workflows completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    workflow_success_uuid2 = "#{UUID.uuid1()}" 
    workflow_success2 = %{
      "id" => workflow_success_uuid2,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_success_uuid2 -> workflow_success2
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid, workflow_success_uuid2]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_success2
  after
    :meck.unload(Workflow)
  end 

  test "resolve_current_workflow - single workflow completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    assert MonitorTask.resolve_current_workflow(upgrade_status) == workflow_success
  after
    :meck.unload(Workflow)
  end

  #==============
  # check_upgrade_status tests
  
  test "check_upgrade_status - workflow completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    assert MonitorTask.check_upgrade_status(mgr, component) == {:ok, :upgrade_completed}
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
  end

  test "check_upgrade_status - workflow not started, failed to execute" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)
    :meck.expect(Workflow, :execute_workflow!, fn _,_,_ -> false end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)
    {:ok, mgr} = ComponentMgr.start_link(component)

    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> :ok end)

    {status, msg} = MonitorTask.check_upgrade_status(mgr, component)
    assert status == :error
    assert msg != nil
  after
    :meck.unload(ComponentStatusMgr)
    :meck.unload(Workflow)
    :meck.unload(MonitorTask)
  end

  test "check_upgrade_status - workflow not started, executed workflow" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)
    :meck.expect(Workflow, :execute_workflow!, fn _,_,_ -> true end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)
    {:ok, mgr} = ComponentMgr.start_link(component)

    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> :ok end)
    
    {status, msg, workflow_id} = MonitorTask.check_upgrade_status(mgr, component)
    assert status == :ok
    assert msg == :upgrade_in_progress
  after
    :meck.unload(ComponentStatusMgr)
    :meck.unload(Workflow)
    :meck.unload(MonitorTask)
  end

  test "check_upgrade_status - workflow in progress" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => false,
      "workflow_error" => false,
      "current_step" => :build
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status
    }
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)
    {:ok, mgr} = ComponentMgr.start_link(component)

    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> :ok end)
    
    {status, msg, workflow_id} = MonitorTask.check_upgrade_status(mgr, component)
    assert status == :ok
    assert msg == :upgrade_in_progress
  after
    :meck.unload(Workflow)
    :meck.unload(MonitorTask)
    :meck.unload(ComponentStatusMgr)
  end

  test "check_upgrade_status - workflow has errored" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => true,
      "current_step" => :build
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status
    }
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)
    {:ok, mgr} = ComponentMgr.start_link(component)

    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> :ok end)
    
    {status, msg} = MonitorTask.check_upgrade_status(mgr, component)
    assert status == :error
    assert msg != nil
  after
    :meck.unload(Workflow)
    :meck.unload(MonitorTask)
    :meck.unload(ComponentStatusMgr)
  end

  #==============
  # execute_monitoring tests
  
  test "execute_monitoring - workflow completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status,
      "status" => "upgrade_in_progress"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)
    :meck.expect(ComponentMgr, :refresh, fn _ -> component end)

    MonitorTask.execute_monitoring(mgr)
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end

  test "execute_monitoring - workflow failed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => true,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status,
      "status" => "upgrade_in_progress"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :save, fn _,_ -> component end)
    :meck.expect(ComponentMgr, :refresh, fn _ -> component end)
    :meck.expect(ComponentMgr, :set_task, fn _,_,_ -> :ok end)

    MonitorTask.execute_monitoring(mgr)
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end

  test "execute_monitoring - upgrade completed" do
    workflow_success_uuid = "#{UUID.uuid1()}" 
    workflow_success = %{
      "id" => workflow_success_uuid,
      "workflow_completed" => true,
      "workflow_error" => false,
    }

    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :get_workflow!, fn _, incoming_workflow_id -> 
      cond do 
        incoming_workflow_id == workflow_success_uuid -> workflow_success
        true -> nil
      end
    end)

    upgrade_status = %{
      "workflows" => [workflow_success_uuid]
    }

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "upgrade_status" => upgrade_status,
      "status" => "upgrade_completed"
    }

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    {:ok, mgr} = ComponentMgr.start_link(component)
    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :refresh, fn _ -> component end)

    MonitorTask.execute_monitoring(mgr)
  after
    :meck.unload(Workflow)
    :meck.unload(ComponentStatusMgr)
    :meck.unload(ComponentMgr)
  end
end