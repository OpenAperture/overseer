#
# == supervisor.ex
#
# This module contains the supervisor for the dispatcher
#
require Logger

defmodule OpenAperture.Overseer.Supervisor do
  use Supervisor

  @moduledoc """
  This module contains the supervisor for the dispatcher
  """

  @doc """
  Specific start_link implementation

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t}
  def start_link do
    Logger.info("Starting OpenAperture.Overseer.Supervisor...")
    :supervisor.start_link(__MODULE__, [])
  end

  @doc """
  GenServer callback - invoked when the server is started.

  ## Options

  The `args` option represents the args to the GenServer.

  ## Return Values

  {:ok, state} | {:ok, state, timeout} | :ignore | {:stop, reason}
  """
  @spec init(term) :: {:ok, term} | {:ok, term, term} | :ignore | {:stop, String.t}
  def init([]) do
    import Supervisor.Spec

    children = [
      # Define workers and child supervisors to be supervised
      worker(OpenAperture.Overseer.Dispatcher, []),
      worker(OpenAperture.Overseer.MessageManager, []),
      worker(OpenAperture.Overseer.Modules.Retriever, []),
      worker(OpenAperture.Overseer.Modules.Manager, []),
      worker(OpenAperture.Overseer.Modules.Listener, []),
      worker(OpenAperture.Overseer.Components.ComponentsMgr, []),
      worker(OpenAperture.Overseer.FleetManagerPublisher, []),
      worker(OpenAperture.Overseer.Clusters.ClustersMonitor, [])
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    supervise(children, opts)
  end
end