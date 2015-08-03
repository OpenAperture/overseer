require Logger

defmodule OpenAperture.Overseer.Clusters.ClustersMonitorTests do
  use ExUnit.Case
  use Timex

  alias OpenAperture.Overseer.Configuration

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange
  alias OpenAperture.ManagerApi.EtcdCluster

  alias OpenAperture.Overseer.Clusters.ClusterMonitor
  alias OpenAperture.Overseer.Clusters.ClustersMonitor

  setup do
    :meck.new(ClusterMonitor, [:passthrough])
    :meck.new(MessagingExchange, [:passthrough])

    on_exit fn ->
      :meck.unload
    end    
    :ok
  end  
  
  # ===================================
  # stop_monitoring_clusters tests

  test "stop_monitoring_clusters - no clusters no cache" do
    ClustersMonitor.stop_monitoring_clusters(%{clusters: %{}}, nil) == %{}
  end  

  test "stop_monitoring_clusters - no clusters with cache" do
    etcd_token = "#{UUID.uuid1()}"
    {:ok, pid} = Agent.start_link(fn -> :ok end)

    clusters = Map.put(%{}, etcd_token, pid)
    state = %{clusters: clusters}

    returned_state = ClustersMonitor.stop_monitoring_clusters(state, nil)
    assert returned_state[:clusters][etcd_token] == nil
  end 

  # ===================================
  # monitor_cluster tests

  test "monitor_cluster - no cache" do
    :meck.expect(ClusterMonitor, :start_link, fn _ -> {:ok, %{}} end)
    etcd_token = "#{UUID.uuid1()}"
    cluster = %{
      "etcd_token" => etcd_token
    }

    {:ok, pid} = Agent.start_link(fn -> :ok end)

    state = %{clusters: %{}}

    returned_state = ClustersMonitor.monitor_cluster(state, cluster)
    assert returned_state[:clusters][etcd_token] != nil
  end 

  test "monitor_cluster - cached" do
    :meck.expect(ClusterMonitor, :start_link, fn _ -> {:ok, %{}} end)
    etcd_token = "#{UUID.uuid1()}"
    cluster = %{
      "etcd_token" => etcd_token
    }

    {:ok, pid} = Agent.start_link(fn -> :ok end)

    cluster_cache = Map.put(%{}, etcd_token, %{})
    state = %{clusters: cluster_cache}

    returned_state = ClustersMonitor.monitor_cluster(state, cluster)
    assert returned_state[:clusters][etcd_token] != nil
  end 

  test "monitor_cluster - failed" do
    :meck.expect(ClusterMonitor, :start_link, fn _ -> {:error, "bad news bears"} end)
    etcd_token = "#{UUID.uuid1()}"
    cluster = %{
      "etcd_token" => etcd_token
    }

    {:ok, pid} = Agent.start_link(fn -> :ok end)

    state = %{clusters: %{}}

    returned_state = ClustersMonitor.monitor_cluster(state, cluster)
    assert returned_state[:clusters][etcd_token] == nil
  end   

  # ===================================
  # monitor_clusters tests

  test "monitor_clusters - nil" do
    :meck.expect(MessagingExchange, :exchange_clusters!, fn _,_ -> nil end)

    state = %{clusters: %{}}

    returned_state = ClustersMonitor.monitor_clusters(state)
    assert returned_state == state
  end 

  test "monitor_clusters - no clusters" do
    :meck.expect(MessagingExchange, :exchange_clusters!, fn _,_ -> [] end)

    state = %{clusters: %{}}

    returned_state = ClustersMonitor.monitor_clusters(state)
    assert returned_state == state
  end 

  test "monitor_cluster - success" do
    etcd_token = "#{UUID.uuid1()}"
    cluster = %{
      "etcd_token" => etcd_token
    }

    :meck.expect(MessagingExchange, :exchange_clusters!, fn _,_ -> [%{"etcd_token" => etcd_token}] end)

    :meck.expect(ClusterMonitor, :start_link, fn _ -> {:ok, %{}} end)

    {:ok, pid} = Agent.start_link(fn -> :ok end)

    state = %{clusters: %{}}

    returned_state = ClustersMonitor.monitor_cluster(state, cluster)
    assert returned_state[:clusters][etcd_token] != nil
  end 

  # ===================================
  # monitor_clusters tests

  test "monitor_cached_clusters - nil" do
    :meck.expect(ClusterMonitor, :monitor, fn _ -> :ok end)

    cluster_cache = Map.put(%{}, "#{UUID.uuid1()}", %{})
    state = %{clusters: cluster_cache}

    returned_state = ClustersMonitor.monitor_cached_clusters(state)
    assert returned_state == :ok
  end   
end