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
    monitor_cluster_units(state[:etcd_token])

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
          unique: true,
          type: :docker_disk_space_percent, 
          severity: :warning, 
          data: %{host_cnt: 0},
          message: "EtcdCluster #{etcd_token} has no associated hosts"
        }       
        SystemEvent.create_system_event!(ManagerApi.get_api, event)
      {:ok, []} -> 
        Logger.error("#{@logprefix}[#{etcd_token}] Unable to perform host checking...no hosts were found in exchange #{exchange_id}!")

        event = %{
          unique: true,
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
      {:ok, node_info} -> monitor_host(Map.keys(node_info), node_info, etcd_token)
    end
  end

  @doc """
  Method to execute monitoring against a host

  ## Option Values

  The `node_info` option defines the Map of all host information

  """
  @spec monitor_host([], Map, String.t) :: term
  def monitor_host([], _node_info, _etcd_token) do
    Logger.debug("Finished reviewing node_info") 
  end

  @doc """
  Method to execute monitoring against a host

  ## Option Values

  The `hosts` option defines the list of hosts to review

  The `node_info` option defines the Map of all host information
  
  """
  @spec monitor_host(List, Map, String.t) :: term
  def monitor_host([returned_hostname | remaining_hostnames], node_info, etcd_token) do
    info = node_info[returned_hostname]

    Logger.debug("Evaluating hostname #{returned_hostname} in node_info #{inspect node_info}")

    event = cond do 
      info["docker_disk_space_percent"] == nil -> %{
          unique: true,        
          type: :docker_disk_space_percent, 
          severity: :error, 
          data: %{
            docker_disk_space_percent: nil,
            hostname: returned_hostname,
            etcd_token: etcd_token
          },
          message: "Host #{returned_hostname} is not reporting the Docker disk space utilization %!"
        }
      info["docker_disk_space_percent"] > 90 -> %{
          unique: true,        
          type: :docker_disk_space_percent, 
          severity: :error, 
          data: %{
            docker_disk_space_percent: info["docker_disk_space_percent"],
            hostname: returned_hostname,
            etcd_token: etcd_token
          },
          message: "Host #{returned_hostname} is reporting a Docker disk space utilization of #{info["docker_disk_space_percent"]}%!"
        }        
      info["docker_disk_space_percent"] > 80 -> %{
          unique: true,
          type: :docker_disk_space_percent, 
          severity: :warning, 
          data: %{
            docker_disk_space_percent: info["docker_disk_space_percent"],
            hostname: returned_hostname,
            etcd_token: etcd_token
          },
          message: "Host #{returned_hostname} is reporting a Docker disk space utilization of #{info["docker_disk_space_percent"]}%!"
        } 
      true -> nil        
    end

    if event != nil do
      Logger.error("#{@logprefix} A system event was generated for #{returned_hostname}:  #{inspect event}")
      SystemEvent.create_system_event!(ManagerApi.get_api, event)
    else
      Logger.debug("#{@logprefix} Host #{returned_hostname} is running as expected")
    end

    monitor_host(remaining_hostnames, node_info, etcd_token)
  end

  @doc """
  Method to monitor units running on a cluster

  ## Option Values

  The `etcd_token` option defines the EtcdToken associated with the cluster
  
  """
  @spec monitor_cluster_units(String.t) :: term
  def monitor_cluster_units(etcd_token) do
    exchange_id = Configuration.get_current_exchange_id

    handler = FleetManagerPublisher.list_unit_states!(etcd_token, exchange_id)
    case RpcHandler.get_response(handler) do
      {:error, reason} -> Logger.error("#{@logprefix}[#{etcd_token}] Received the following error retrieving unit states:  #{inspect reason}")
      #i.e. build slaves
      {:ok, []} -> Logger.debug("#{@logprefix}[#{etcd_token}] Cluster #{etcd_token} is not running any units") 
      #load error occurred
      {:ok, nil} -> 
        Logger.error("#{@logprefix}[#{etcd_token}] Unable to perform states checking...invalid states were found in cluster #{etcd_token}!")

        event = %{
          unique: true,
          type: :failed_unit, 
          severity: :warning, 
          data: %{
            etcd_token: etcd_token,
            host_cnt: nil
            },
          message: "EtcdCluster #{etcd_token} failed to return unit states!"
        }       
        SystemEvent.create_system_event!(ManagerApi.get_api, event)      
      {:ok, units} -> 
        monitor_unit_instances(units, etcd_token, 0)
        monitor_units(units, etcd_token)
    end
  end

  @doc """
  Method to execute monitoring of a unit

  ## Option Values

  The `etcd_token` option defines the EtcdToken associated with the cluster

  """
  @spec monitor_unit_instances([], String.t, term) :: term
  def monitor_unit_instances([], _etcd_token, _failure_count) do
    Logger.debug("Finished reviewing units") 
  end

  @doc """
  Method to execute monitoring of a unit

  ## Option Values

  The `etcd_token` option defines the EtcdToken associated with the cluster

  """
  @spec monitor_unit_instances(List, String.t, term) :: term
  def monitor_unit_instances([unit| remaining_units] = all_units, etcd_token, failure_count) do
    event = cond do 
      #give failed units 3 tries before generating an error
      unit["systemdActiveState"] == "failed" && failure_count < 3 ->
        :timer.sleep(10_000)
        #TODO:  need to refresh the unit state first
        monitor_unit_instances(all_units, etcd_token, failure_count + 1)
      unit["systemdActiveState"] == "failed" -> %{
        unique: true,        
        type: :failed_unit, 
        severity: :warning, 
        data: %{
          unit_name: unit["name"],
          etcd_token: etcd_token
        },
        message: "Unit #{unit["name"]} is in a failed state!"
        } 
      true -> nil        
    end

    if event != nil do
      Logger.error("#{@logprefix} A system event was generated for unit #{unit["name"]}:  #{inspect event}")
      SystemEvent.create_system_event!(ManagerApi.get_api, event)
    else
      Logger.debug("#{@logprefix} Unit #{unit["name"]} is running as expected")
    end

    monitor_unit_instances(remaining_units, etcd_token, 0)
  end

  @doc """
  Method to determine if there is at least 1 instance of each unit name running

  ## Option Values

  The `units` option defines a List of Units to review

  The `etcd_token` option defines the EtcdToken associated with the cluster

  """
  @spec monitor_units(List, String.t) :: term
  def monitor_units(units, etcd_token) do
    if units == nil || length(units) == 0 do
      Logger.debug("#{@logprefix} There are no units in cluster #{etcd_token} to review")
    else
      units_by_name = Enum.reduce units, %{}, fn(unit, units_by_name) ->
        running_units = units_by_name[unit["name"]]
        if running_units == nil do
          running_units = []
        end

        if unit["systemdActiveState"] == "failed" do
          units_by_name
        else
          Map.put(units_by_name, unit["name"], running_units ++ [unit])
        end
      end

      Enum.reduce Map.keys(units_by_name), nil, fn (unit_name, _errors) ->
        running_units = units_by_name[unit_name]
        if length(running_units) == 0 do
          event = %{
            unique: true,        
            type: :failed_unit, 
            severity: :error, 
            data: %{
              unit_name: unit_name,
              etcd_token: etcd_token
            },
            message: "Unit #{unit_name} has no running instances!"
          } 

          Logger.error("#{@logprefix} A system event was generated for unit #{unit_name}:  #{inspect event}")
          SystemEvent.create_system_event!(ManagerApi.get_api, event)          
        end
      end
    end
  end
end