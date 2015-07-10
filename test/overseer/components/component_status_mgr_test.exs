defmodule OpenAperture.Overseer.Components.ComponentStatusMgrTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Components.ComponentStatusMgr
  alias OpenAperture.Overseer.Components.ComponentMgr

  alias OpenAperture.Overseer.Components.MonitorTask

  # ===================================
  # refresh tests

  test "refresh - failed " do
    :meck.new(MonitorTask, [:passthrough])
    :meck.expect(MonitorTask, :create, fn _ -> nil end)

    component = %{
      "id" => "#{UUID.uuid1()}",
      "type" => "test",
      "status" => "upgrade_in_progress"
    }

    :meck.new(ComponentMgr, [:passthrough])
    :meck.expect(ComponentMgr, :component, fn _ -> component end)
    :meck.expect(ComponentMgr, :current_upgrade_task, fn _ -> %{} end)

    state = %{
      component_mgr: %{}
    }
    ComponentStatusMgr.check_for_upgrade(state)
  after
    :meck.unload(ComponentMgr)
    :meck.unload(MonitorTask)
  end

  #no additional tests because i can't meck out the timer
end