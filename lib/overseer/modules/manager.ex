require Logger

defmodule OpenAperture.Overseer.Modules.Manager do
  use GenServer
  use Timex

  alias OpenAperture.Overseer.Modules.Listener

 	alias OpenAperture.ManagerApi.MessagingExchangeModule
	
  @moduledoc """
  This module contains the GenServer for managing Module communication processes
  """  

  @doc """
  Specific start_link implementation

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}	
  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Method to set the known list of system modules into the manager

  ## Options

  The `modules` option is a list of system modules

  ## Return Values

  :ok
  """
  @spec set_modules(List) :: :ok
  def set_modules(modules) do
  	GenServer.cast(__MODULE__, {:set_modules, modules})
  end

  @doc """
  GenServer callback for handling the :set_modules event.  This method
  will update the module list and stop/start listeners are needed

  {:noreply, state}
  """
  @spec handle_cast(pid, term) :: {:noreply, Map}
  def handle_cast({:set_modules, modules}, state) do
  	state = start_listeners(state, modules)
  	state = stop_listeners(state, find_deleted_modules(state, modules))
  	{:noreply, state}
  end

  @doc """
  Method to identify any modules which are no longer alive

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to start

  """
  @spec find_deleted_modules(Map, List) :: Map
  def find_deleted_modules(state, modules) do
  	if state[:modules] == nil || Map.size(state[:modules]) == 0 do
  		[]
  	else
  		new_modules = if modules == nil || length(modules) == 0 do
  			%{}
  		else
  			Enum.reduce modules, %{}, fn(module, new_modules) ->
  				Map.put(new_modules, module["hostname"], module)
  			end
  		end

  		Enum.reduce Map.keys(state[:modules]), [], fn(hostname, invalid_modules) ->
  			if Map.has_key?(new_modules, hostname) do
  				invalid_modules
  			else
  				invalid_modules ++ [Listener.get_module(state[:modules][hostname])]
  			end
  		end
  	end
  end

  @doc """
  Method to "start" (subscribe to queue) a list of Modules

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to start

  """
  @spec start_listeners(Map, []) :: Map
  def start_listeners(state, []) do
  	state
  end

  @doc """
  Method to "start" (subscribe to queue) a list of Modules

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to start

  """
  @spec start_listeners(Map, List) :: Map
  def start_listeners(state, [module|remaining_modules]) do
  	state = cond do
  		state[:modules][module["hostname"]] != nil -> state
  		true ->
  			case Listener.start_link(module) do
	  			{:ok, listener} ->
            Logger.debug("Successfully created listener #{inspect listener} for module #{module["hostname"]}...")
	  				Listener.start_listening(listener)
            modules_state = Map.put(state[:modules], module["hostname"], listener)
	  				Map.put(state, :modules, modules_state)
	  			{:error, reason} -> 
	  				Logger.error("Failed to start listener for module #{module["hostname"]}:  #{inspect reason}")
	  				state
	  		end
  	end
  	start_listeners(state, remaining_modules)
  end

  @doc """
  Method to "stop" (unsubscribe from queue) a list of Modules

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to stop

  """
  @spec stop_listeners(Map, nil) :: Map
  def stop_listeners(state, nil) do
  	state
  end

  @doc """
  Method to "stop" (unsubscribe from queue) a list of Modules

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to stop

  """
  @spec stop_listeners(Map, []) :: Map
  def stop_listeners(state, []) do
  	state
  end

  @doc """
  Method to "stop" (unsubscribe from queue) a list of Modules

  ## Options

	The `state` option is the state of the GenServer

	The second option is the list of modules to stop

  """
  @spec stop_listeners(Map, List) :: Map
  def stop_listeners(state, [module|remaining_modules]) do
  	state = if state[:modules][module["hostname"]] != nil do
  		Listener.stop_listening(state[:modules][module["hostname"]])

	  	modules_state = Map.delete(state[:modules], module["hostname"])
	  	Map.put(state, :modules, modules_state)
	  else
			state
		end

		stop_listeners(state, remaining_modules)
  end

  @doc """
  Method to identify and update or delete any "inactive" listeners.  A listener is defined as "inactive" if:
  	* The last updated_at time is > 10 minutes - set status to :inactive
  	* The last updated_at time is > 20 minutes - delete reference

  ## Options

	The `state` option is the state of the GenServer

  """
  @spec inactivate_listeners(Map) :: term
  def inactivate_listeners(state) do
		Enum.reduce state[:modules], [], fn(listener, _inactive_modules) ->
			module = Listener.get_module(listener)

	    try do
	      {:ok, updated_at} = DateFormat.parse(module["updated_at"], "{RFC1123}")
	      updated_at_secs = Date.convert(updated_at, :secs) #since epoch
	      
	    	now = Date.now #utc
	    	now_secs = Date.convert(now, :secs) #since epoch      

				diff_seconds = now_secs - updated_at_secs
				cond do 
					#if the module hasn't been updated in 20 minutes, delete it
					#don't worry about stopping the listener and updating state, that will happen next refresh
					diff_seconds > 1200 ->
						Logger.debug("Module #{module["hostname"]} has not been updated in at least 20 minutes, delete it")
						case MessagingExchangeModule.delete_module!(Application.get_env(:openaperture_overseer_api, :exchange_id), module[:hostname]) do
					    true -> Logger.debug("Successfully deleted module #{module["hostname"]}")
					    false -> Logger.error("Failed to deleted module #{module["hostname"]}!")
					  end
					#if the module hasn't been updated in 10 minutes, inactive it (and update the state)
					diff_seconds > 600 ->
						Logger.debug("Module #{module["hostname"]} has not been updated in at least 10 minutes, inactive it")
						module = Map.put(module, :state, :inactive)
						case MessagingExchangeModule.create_module!(Application.get_env(:openaperture_overseer_api, :exchange_id), module) do
					    true -> 
					      Logger.debug("Successfully inactivated module #{module["hostname"]}")
					      Listener.set_module(listener, module)
					    false -> Logger.error("Failed to inactivated module #{module["hostname"]}!")
					  end
					true -> Logger.debug("Module #{module["hostname"]} is still active")
				end
	    rescue e ->
	      Logger.error("An error occurred parsing updated_at time for module #{module["hostname"]}:  #{inspect e}")
	    end			
		end  	
  end
end