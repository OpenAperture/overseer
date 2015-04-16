defmodule OpenAperture.Overseer.Modules.RetrieverTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Modules.Retriever
  alias OpenAperture.Overseer.Modules.Manager
  alias OpenAperture.ManagerApi.MessagingExchangeModule
  
  # ===================================
  # refresh_modules tests

  test "refresh_modules - success" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :list!, fn _ -> [] end)

    :meck.new(Manager, [:passthrough])
    :meck.expect(Manager, :set_modules, fn _ -> :ok end)

    assert Retriever.refresh_modules == []
  after
    :meck.unload(MessagingExchangeModule)
    :meck.unload(Manager)
  end

  test "refresh_modules - failure" do
    :meck.new(MessagingExchangeModule, [:passthrough])
    :meck.expect(MessagingExchangeModule, :list!, fn _ -> nil end)

    :meck.new(Manager, [:passthrough])
    :meck.expect(Manager, :set_modules, fn _ -> :ok end)

    assert Retriever.refresh_modules == nil
  after
    :meck.unload(MessagingExchangeModule)
    :meck.unload(Manager)
  end  
end