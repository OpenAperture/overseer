defmodule OpenAperture.Overseer.Clusters.ClusterMonitorTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Configuration
  alias OpenAperture.Overseer.FleetManagerPublisher
  alias OpenAperture.Messaging.AMQP.RpcHandler

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent

  alias OpenAperture.Overseer.Clusters.ClusterMonitor

  setup do
    :meck.new(SystemEvent, [:passthrough])
    :meck.new(FleetManagerPublisher, [:passthrough])
    :meck.new(RpcHandler, [:passthrough])

    on_exit fn ->
      :meck.unload
    end    
    :ok
  end  
  
  # ===================================
  # monitor_host tests

  test "monitor_host - empty list" do
    ClusterMonitor.monitor_host([], %{}, "#{UUID.uuid1()}")
  end

  test "monitor_host - docker_disk_space_percent missing" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{})

    ClusterMonitor.monitor_host(Map.keys(node_info), node_info, "#{UUID.uuid1()}")
  end

  test "monitor_host - docker_disk_space_percent ok" do

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 50})

    ClusterMonitor.monitor_host(Map.keys(node_info), node_info, "#{UUID.uuid1()}")
  end

  test "monitor_host - docker_disk_space_percent warning" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 85})

    ClusterMonitor.monitor_host(Map.keys(node_info), node_info, "#{UUID.uuid1()}")
  end  

  test "monitor_host - docker_disk_space_percent error" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    ClusterMonitor.monitor_host(Map.keys(node_info), node_info, "#{UUID.uuid1()}")
  end 

  # ===================================
  # monitor_hosts tests

  test "monitor_hosts - failure" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:error, "bad news bears"} end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_hosts(etcd_token, hosts)
  end   

  test "monitor_hosts - nil response" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:ok, nil} end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_hosts(etcd_token, hosts)
  end  

  test "monitor_hosts - success" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 30})

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:ok, node_info} end)

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_hosts(etcd_token, hosts)
  end 

  # ===================================
  # monitor_cluster tests

  test "monitor_cluster - failure" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(FleetManagerPublisher, :list_machines!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:error, "bad news bears"} end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_cluster(etcd_token)
  end   

  test "monitor_cluster - nil hosts" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(FleetManagerPublisher, :list_machines!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:ok, nil} end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_cluster(etcd_token)
  end

  test "monitor_cluster - empty hosts" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> %{} end)
    :meck.expect(FleetManagerPublisher, :list_machines!, fn _,_ -> %{} end)
    :meck.expect(RpcHandler, :get_response, fn _ -> {:ok, []} end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_cluster(etcd_token)
  end

  test "monitor_cluster - success" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    hostname = "#{UUID.uuid1()}"
    node_info = %{}
    node_info = Map.put(node_info, hostname, %{"docker_disk_space_percent" => 95})

    hosts = [%{"primaryIP" => hostname}]

    :meck.expect(FleetManagerPublisher, :node_info!, fn _,_ -> :node end)
    :meck.expect(FleetManagerPublisher, :list_machines!, fn _,_ -> :machines end)
    :meck.expect(RpcHandler, :get_response, fn type -> 
      if type == :node do
        {:ok, node_info} 
      else
        {:ok, hosts}
      end
    end)

    etcd_token = "#{UUID.uuid1()}"

    ClusterMonitor.monitor_cluster(etcd_token)
  end

  # ===================================
  # monitor_cluster_units tests

  test "monitor_cluster_units - nil units" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)
    :meck.expect(FleetManagerPublisher, :list_unit_states!, fn _,_ -> :units end)
    :meck.expect(RpcHandler, :get_response, fn type -> 
      {:ok, nil}
    end)

    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    ClusterMonitor.monitor_cluster_units("#{UUID.uuid1()}")
  end

  test "monitor_cluster_units - empty units" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)
    :meck.expect(FleetManagerPublisher, :list_unit_states!, fn _,_ -> :units end)
    :meck.expect(RpcHandler, :get_response, fn type -> 
      {:ok, []}
    end)

    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)

    ClusterMonitor.monitor_cluster_units("#{UUID.uuid1()}")
  end

  test "monitor_cluster_units - units" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)
    :meck.expect(FleetManagerPublisher, :list_unit_states!, fn _,_ -> :units end)
    :meck.expect(RpcHandler, :get_response, fn type -> 
      {:ok, [%{"systemdActiveState" => "active"}]}
    end)

    ClusterMonitor.monitor_cluster_units("#{UUID.uuid1()}")
  end

  # ===================================
  # monitor_units tests

  test "monitor_units - empty" do
    ClusterMonitor.monitor_units([], "#{UUID.uuid1()}")
  end

  test "monitor_units - active unit" do
    ClusterMonitor.monitor_units([%{"systemdActiveState" => "active"}], "#{UUID.uuid1()}")
  end

  test "monitor_units - failed unit" do
    :meck.expect(SystemEvent, :create_system_event!, fn _,_ -> :ok end)
        
    ClusterMonitor.monitor_units([%{"systemdActiveState" => "failed"}], "#{UUID.uuid1()}")
  end
end