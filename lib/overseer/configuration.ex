#
# == configuration.ex
#
# This module contains the logic to retrieve configuration from either the environment or configuration files
#
defmodule OpenAperture.Overseer.Configuration do

  @doc """
  Method to retrieve the currently assigned exchange id

  ## Options

  ## Return values

  The exchange identifier
  """
  @spec get_current_exchange_id() :: String.t
  def get_current_exchange_id do
    get_config("EXCHANGE_ID", :openaperture_overseer, :exchange_id)
  end

  @doc """
  Method to retrieve the currently assigned exchange id

  ## Options

  ## Return values

  The exchange identifier
  """
  @spec get_current_broker_id() :: String.t
  def get_current_broker_id do
    get_config("BROKER_ID", :openaperture_overseer, :broker_id)
  end

  @doc """
  Method to retrieve the currently assigned queue name (for "overseer")

  ## Options

  ## Return values

  The exchange identifier
  """
  @spec get_current_queue_name() :: String.t
  def get_current_queue_name do
    get_config("QUEUE_NAME", :openaperture_overseer, :queue_name)
  end

  @doc """
  Method to retrieve the currently assigned queue name (for "system_modules")

  ## Options

  ## Return values

  The exchange identifier
  """
  @spec get_current_system_modules_queue_name() :: String.t
  def get_current_system_modules_queue_name do
    get_config("SYSTEM_MODULES_QUEUE_NAME", :openaperture_overseer, :system_modules_queue_name)
  end

  @doc false
  # Method to retrieve a configuration option from the environment or config settings
  #
  ## Options
  #
  # The `env_name` option defines the environment variable name
  #
  # The `application_config` option defines the config application name (atom)
  #
  # The `config_name` option defines the config variable name (atom)
  #
  ## Return values
  #
  # Value
  #
  @spec get_config(String.t, term, term) :: String.t
  defp get_config(env_name, application_config, config_name) do
    System.get_env(env_name) || Application.get_env(application_config, config_name)
  end
end