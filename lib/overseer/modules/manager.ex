require Logger

defmodule OpenAperture.Overseer.Modules.Manager do
  use GenServer
  use Timex

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
    inactivate_listeners(modules)
  	{:noreply, state}
  end

  @doc """
  Method to identify and update or delete any "inactive" listeners.  A listener is defined as "inactive" if:
  	* The last updated_at time is > 10 minutes - set status to :inactive
  	* The last updated_at time is > 20 minutes - delete reference

  ## Options

	The `modules` option is the list of modules

  """
  @spec inactivate_listeners(Map) :: term
  def inactivate_listeners(modules) do
    if modules == nil || length(modules) == 0 do
      Logger.debug("[Manager] There are no modules to review for inactivation")
    else
      Logger.debug("[Manager] Reviewing #{length(modules)} modules for inactivation...")
      Enum.reduce modules, [], fn(module, _inactive_modules) ->
        try do
          diff_seconds = get_last_updated_seconds(module)
          Logger.debug("[Manager] Reviewing module #{module["hostname"]} for activation status (last updated #{diff_seconds} seconds ago):  #{inspect module}")
        
          cond do 
            module["status"] == "inactive" && diff_seconds > 600 ->
              Logger.debug("[Manager] Module #{module["hostname"]} has not been updated in at least 20 minutes, delete it")
              case MessagingExchangeModule.delete_module!(Application.get_env(:openaperture_overseer_api, :exchange_id), module["hostname"]) do
                true -> Logger.debug("[Manager] Successfully deleted module #{module["hostname"]}")
                false -> Logger.error("[Manager] Failed to deleted module #{module["hostname"]}!")
              end
            module["status"] != "inactive" && diff_seconds > 600 ->
              module = Map.put(module, "status", :inactive)
              Logger.debug("[Manager] Module #{module["hostname"]} has not been updated in at least 10 minutes, inactive it")
              case MessagingExchangeModule.create_module!(Application.get_env(:openaperture_overseer_api, :exchange_id), module) do
                nil -> Logger.error("[Manager] Failed to inactivated module #{module["hostname"]}!")
                _ -> Logger.debug("[Manager] Successfully inactivated module #{module["hostname"]}")
              end
            true -> Logger.debug("[Manager] Module #{module["hostname"]} is still active")
          end
        rescue e ->
          Logger.error("[Manager] An error occurred parsing updated_at time for a module:  #{inspect e}")
        end     
      end 
    end 	
  end

  defp get_last_updated_seconds(module) do
    if module["updated_at"] == nil || String.length(module["updated_at"]) == 0 do
      Logger.error("[Manager] Unable to review module #{module["hostname"]} because it does not have a valid updated_at time!")
      -1
    else
     {:ok, updated_at} = DateFormat.parse(module["updated_at"], "{RFC1123}")
      updated_at_secs = Date.convert(updated_at, :secs) #since epoch
      
      now = Date.now #utc
      now_secs = Date.convert(now, :secs) #since epoch      

      now_secs - updated_at_secs
    end    
  end
end