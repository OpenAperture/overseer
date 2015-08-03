require Logger

defmodule OpenAperture.Overseer.Clusters.ClusterMonitor do
  use GenServer

  alias OpenAperture.Overseer.Configuration
  alias OpenAperture.Overseer.FleetManagerPublisher
  alias OpenAperture.Messaging.AMQP.RpcHandler

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent

  @logprefix "[Clusters][ClusterMonitor]"

  @moduledoc """
  This module contains the GenServer for monitoring a cluster in the associated exchange
  """  

  @doc """
  Specific start_link implementation

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t()}  
  def start_link(cluster) do
    Logger.debug("#{@logprefix}[#{cluster["etcd_token"]}] Starting...")
    GenServer.start_link(__MODULE__, %{cluster: cluster, etcd_token: cluster["etcd_token"]})
  end

  @doc """
  Method to begin a Monitoring session

  ## Option Values

  The `state` option is the GenServer's state

  ## Return Values

  :ok
  """
  @spec monitor(pid) :: :ok
  def monitor(monitor) do
    GenServer.cast(monitor, {:monitor})
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
    monitor_cluster(state[:etcd_token])
    {:noreply, state}
  end

  @doc """
  Method to execute monitoring against a cluster

  ## Option Values

  The `etcd_token` option defines the etcd token for the cluster

  """
  @spec monitor_cluster(String.t) :: term
  def monitor_cluster(etcd_token) do
    exchange_id = Configuration.get_current_exchange_id

    handler = FleetManagerPublisher.list_machines!(etcd_token, exchange_id)
    case RpcHandler.get_response(handler) do
      {:error, reason} -> Logger.error("#{@logprefix}[#{etcd_token}] Received the following error retrieving node_info:  #{inspect reason}")
      {:ok, nil} -> 
        Logger.error("#{@logprefix}[#{etcd_token}] Unable to perform host checking...invalid hosts were found in exchange #{exchange_id}!")

        event = %{
        type: :docker_disk_space_percent, 
          severity: :warning, 
          data: %{host_cnt: 0},
          message: "EtcdCluster #{etcd_token} has no associated hosts"
        }       
        SystemEvent.create_system_event!(ManagerApi.get_api, event)
      {:ok, []} -> 
        Logger.error("#{@logprefix}[#{etcd_token}] Unable to perform host checking...no hosts were found in exchange #{exchange_id}!")

        event = %{
        type: :docker_disk_space_percent, 
          severity: :warning, 
          data: %{host_cnt: 0},
          message: "EtcdCluster #{etcd_token} has no associated hosts"
        }       
        SystemEvent.create_system_event!(ManagerApi.get_api, event)        
      {:ok, hosts} -> monitor_hosts(etcd_token, hosts)
    end
  end

  @doc """
  Method to execute monitoring against a set of hosts

  ## Option Values

  The `etcd_token` option defines the etcd token for the cluster

  The `hosts` option defines the list of hosts in the cluster

  """
  @spec monitor_hosts(String.t, List) :: term
  def monitor_hosts(etcd_token, hosts) do
    hostnames = Enum.reduce hosts, [], fn(host, hostnames) ->
      hostnames ++ [host["primaryIP"]]
    end

    handler = FleetManagerPublisher.node_info!(Configuration.get_current_exchange_id, hostnames)
    case RpcHandler.get_response(handler) do
      {:error, reason} -> Logger.error("#{@logprefix}[#{etcd_token}] Received the following error retrieving node_info:  #{inspect reason}")
      {:ok, nil} -> Logger.error("#{@logprefix}[#{etcd_token}] No node_info was returned!")
      {:ok, node_info} -> monitor_host(Map.keys(node_info), node_info)
    end 
  end

  @doc """
  Method to execute monitoring against a host

  ## Option Values

  The `node_info` option defines the Map of all host information

  """
  @spec monitor_host([], Map) :: term
  def monitor_host([], _node_info) do
    Logger.debug("Finished reviewing node_info") 
  end

  @doc """
  Method to execute monitoring against a host

  ## Option Values

  The `hosts` option defines the list of hosts to review

  The `node_info` option defines the Map of all host information
  
  """
  @spec monitor_host(List, Map) :: term
  def monitor_host([returned_hostname | remaining_hostnames], node_info) do
    info = node_info[returned_hostname]

    event = cond do 
      info[:docker_disk_space_percent] == nil -> %{
        type: :docker_disk_space_percent, 
          severity: :error, 
          data: %{docker_disk_space_percent: nil},
          message: "Host #{returned_hostname} is not reporting the Docker disk space %!"
        }
      info[:docker_disk_space_percent] > 90 -> %{
        type: :docker_disk_space_percent, 
          severity: :error, 
          data: %{docker_disk_space_percent: info[:docker_disk_space_percent]},
          message: "Host #{returned_hostname} is reporting a Docker disk space of #{info[:docker_disk_space_percent]}%!"
        }        
      info[:docker_disk_space_percent] > 80 -> %{
        type: :docker_disk_space_percent, 
          severity: :warning, 
          data: %{docker_disk_space_percent: info[:docker_disk_space_percent]},
          message: "Host #{returned_hostname} is reporting a Docker disk space of #{info[:docker_disk_space_percent]}%!"
        } 
      true -> nil        
    end

    if event != nil do
      Logger.error("#{@logprefix} A system event was generated for #{returned_hostname}:  #{inspect event}")
      SystemEvent.create_system_event!(ManagerApi.get_api, event)
    else
      Logger.debug("#{@logprefix} Host #{returned_hostname} is running as expected")
    end

    monitor_host(remaining_hostnames, node_info)
  end
end