require Logger

defmodule OpenAperture.Overseer.Clusters.ClustersMonitor do
  use GenServer

  alias OpenAperture.Overseer.Configuration

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange

  alias OpenAperture.Overseer.Clusters.ClusterMonitor

  @logprefix "[Clusters][ClustersMonitor]"

  @moduledoc """
  This module contains the GenServer for monitoring all of the clusters in the associated exchange
  """

  @doc """
  Specific start_link implementation

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}
  def start_link() do
    Logger.debug("#{@logprefix} Starting...")
    case GenServer.start_link(__MODULE__, %{clusters: %{}}, name: __MODULE__) do
      {:ok, pid} ->
        if Application.get_env(:autostart, :clusters_monitor, true) do
          GenServer.cast(pid, {:monitor})
        end
        {:ok, pid}
      {:error, reason} -> raise "#{@logprefix} Failed to start:  #{inspect reason}"
    end
  end

  @doc """
  GenServer callback to begin a Monitoring session

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

  {:noreply, state}
  """
  @spec handle_cast({:monitor}, Map) :: {:noreply, Map}
  def handle_cast({:monitor}, state) do
    #sleep for up to half an hour
    sleep_seconds = :random.uniform(1800)
    if sleep_seconds < 60 do
      sleep_seconds = 60
    end
    Logger.debug("[#{@logprefix} Sleeping for #{sleep_seconds} seconds before reviewing clusters...")
    :timer.sleep(sleep_seconds * 1000)

    updated_state = monitor_clusters(state)
    monitor_cached_clusters(updated_state)

    GenServer.cast(self, {:monitor})

    {:noreply, updated_state}
  end

  @doc """
  Method to request all cluster monitors start a monitoring session

  ## Option Values

  The `state` option is the GenServer's state
  """
  @spec monitor_cached_clusters(Map) :: Map
  def monitor_cached_clusters(state) do
    Enum.reduce Map.values(state[:clusters]), nil, fn monitor, _result ->
      ClusterMonitor.monitor(monitor)
    end
  end

  @doc """
  Method to start a monitor for all clusters

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

  state
  """
  @spec monitor_clusters(Map) :: Map
  def monitor_clusters(state) do
    exchange_id = Configuration.get_current_exchange_id

    clusters = MessagingExchange.exchange_clusters!(ManagerApi.get_api, exchange_id)
    cond do
      clusters == nil ->
        Logger.error("#{@logprefix} Unable to load clusters associated with exchange #{exchange_id}!")
        state
      clusters == [] ->
        Logger.debug("#{@logprefix} There are no clusters associated to exchange #{exchange_id}")
        stop_monitoring_clusters(state)
      true ->
        {updated_state, remaining_clusters} = Enum.reduce clusters, {state, Map.keys(state[:clusters])}, fn(cluster, {updated_state, remaining_clusters}) ->
          {monitor_cluster(updated_state, cluster), List.delete(remaining_clusters, cluster["etcd_token"])}
        end

        stop_monitoring_clusters(updated_state, remaining_clusters)
    end
  end

  @doc """
  Method to start a monitor for a cluster

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

  state
  """
  @spec monitor_cluster(Map, Map) :: Map
  def monitor_cluster(state, cluster) do
    if state[:clusters][cluster["etcd_token"]] == nil do
      case ClusterMonitor.start_link(cluster) do
        {:ok, monitor} ->
          Logger.debug("#{@logprefix} Starting a new monitor for cluster #{cluster["etcd_token"]}")
          cluster_cache = state[:clusters]
          cluster_cache = Map.put(cluster_cache, cluster["etcd_token"], monitor)
          Map.put(state, :clusters, cluster_cache)
        {:error, reason} ->
          Logger.error("#{@logprefix} Failed to start Cluster monitor for cluster #{cluster["etcd_token"]}:  #{inspect reason}")
          state
      end
    else
      Logger.debug("#{@logprefix} A monitor already exists for cluster #{cluster["etcd_token"]}")
      state
    end
  end

  @doc """
  Method to stop a monitor for a cluster or clusters

  ## Option Values

  The `state` option is the GenServer's state

  The `clusters` option defines the list of clusters to stop monitoring

  ## Return Values

  state
  """
  @spec stop_monitoring_clusters(Map, List) :: Map
  def stop_monitoring_clusters(state, clusters \\ nil) do
    if clusters == nil do
      clusters = Map.keys(state[:clusters])
    end

    unless clusters == nil || length(clusters) == 0 do
      Enum.reduce clusters, state, fn etcd_token, updated_state ->
        monitor = updated_state[:clusters][etcd_token]
        if monitor != nil do
          Logger.info("#{@logprefix} Stopping monitor for cluster #{etcd_token}")
          Process.exit(monitor, :normal)
        else
          Logger.error("#{@logprefix} Failed to stop monitor for cluster #{etcd_token} - monitor does not exist!")
        end
        cached_clusters = Map.delete(updated_state[:clusters], etcd_token)
        Map.put(updated_state, :clusters, cached_clusters)
      end
    else
      state
    end
  end
end