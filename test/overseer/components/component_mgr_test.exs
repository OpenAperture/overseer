defmodule OpenAperture.Overseer.Components.ComponentMgrTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Components.ComponentsMgr
  alias OpenAperture.Overseer.Components.ComponentMgr
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange
  alias OpenAperture.ManagerApi.SystemComponentRef
  alias OpenAperture.ManagerApi.SystemComponent

  alias OpenAperture.Overseer.Configuration
  alias OpenAperture.Overseer.Components.ComponentStatusMgr
  alias OpenAperture.Overseer.Components.UpgradeTask

  alias OpenAperture.Overseer.Configuration
  
  # ===================================
  # refresh tests

  test "refresh - failed " do
    :meck.new(SystemComponent, [:passthrough])
    :meck.expect(SystemComponent, :get_system_component!, fn _,_ -> nil end)

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    returned_component = ComponentMgr.refresh(mgr)
    assert returned_component["id"] == component["id"]
  after
    :meck.unload(SystemComponent)
    :meck.unload(ComponentStatusMgr)
  end

  test "refresh - success " do
    refreshed_component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }

    :meck.new(SystemComponent, [:passthrough])
    :meck.expect(SystemComponent, :get_system_component!, fn _,_ -> refreshed_component end)

    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    returned_component = ComponentMgr.refresh(mgr)
    assert returned_component["id"] == refreshed_component["id"]
  after
    :meck.unload(SystemComponent)
    :meck.unload(ComponentStatusMgr)
  end

  # ===================================
  # component tests

  test "component - success " do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    returned_component = ComponentMgr.component(mgr)
    assert returned_component["id"] == component["id"]
  after
    :meck.unload(ComponentStatusMgr)
  end

  # ===================================
  # save tests

  test "save - failed " do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    :meck.new(SystemComponent, [:passthrough])
    :meck.expect(SystemComponent, :update_system_component!, fn _,_,_ -> nil end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)

    new_component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }

    returned_component = ComponentMgr.save(mgr, new_component)
    assert returned_component["id"] == component["id"]
  after
    :meck.unload(SystemComponent)
    :meck.unload(ComponentStatusMgr)
  end

  test "save - success " do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    new_component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }

    :meck.new(SystemComponent, [:passthrough])
    :meck.expect(SystemComponent, :update_system_component!, fn _,_,_ -> :ok end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    returned_component = ComponentMgr.save(mgr, new_component)
    assert returned_component["id"] == new_component["id"]
  after
    :meck.unload(SystemComponent)
    :meck.unload(ComponentStatusMgr)
  end

  # ===================================
  # request_upgrade tests

  test "request_upgrade - new task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    :meck.new(UpgradeTask, [:passthrough])
    :meck.expect(UpgradeTask, :create, fn _ -> %{} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)

    returned_task = ComponentMgr.request_upgrade(mgr)
    assert returned_task == %{}
  after
    :meck.unload(UpgradeTask)
    :meck.unload(ComponentStatusMgr)
  end

  test "request_upgrade - upgrade task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :upgrade_task, %{})

    returned_task = ComponentMgr.request_upgrade(mgr)
    assert returned_task == %{}
  after
    :meck.unload(ComponentStatusMgr)
  end

  test "request_upgrade - monitoring task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :monitoring_task, %{})

    returned_task = ComponentMgr.request_upgrade(mgr)
    assert returned_task == %{}
  after
    :meck.unload(ComponentStatusMgr)
  end

  # ===================================
  # set_task tests

  test "set_task - set task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :monitoring_task, %{})

    returned_task = ComponentMgr.request_upgrade(mgr)
    assert returned_task == %{}
  after
    :meck.unload(ComponentStatusMgr)
  end

  # ===================================
  # current_upgrade_task tests

  test "current_upgrade_task - no current task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)

    returned_task = ComponentMgr.current_upgrade_task(mgr)
    assert returned_task == nil
  after
    :meck.unload(ComponentStatusMgr)
  end

  test "current_upgrade_task - upgrade task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :upgrade_task, %{})

    returned_task = ComponentMgr.current_upgrade_task(mgr)
    assert returned_task != nil
  after
    :meck.unload(ComponentStatusMgr)
  end

  test "current_upgrade_task - monitoring task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :monitoring_task, %{})

    returned_task = ComponentMgr.current_upgrade_task(mgr)
    assert returned_task != nil
  after
    :meck.unload(ComponentStatusMgr)
  end

  test "current_upgrade_task - all task" do
    :meck.new(ComponentStatusMgr, [:passthrough])
    :meck.expect(ComponentStatusMgr, :start_link, fn _ -> {:ok, nil} end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test"
    }
    {:ok, mgr} = ComponentMgr.start_link(component)
    ComponentMgr.set_task(mgr, :upgrade_task, %{})
    ComponentMgr.set_task(mgr, :monitoring_task, %{test: ""})

    returned_task = ComponentMgr.current_upgrade_task(mgr)
    assert returned_task == %{test: ""}
  after
    :meck.unload(ComponentStatusMgr)
  end
end