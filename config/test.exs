# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for third-
# party users, it should be done in your mix.exs file.

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]

config :autostart,
	register_queues: false,
	retrieve_modules: false,
	start_listening: false,
	component_mgr: false,
	resolve_system_components: false,
	clusters_monitor: false

config :openaperture_manager_api, 
	manager_url: System.get_env("MANAGER_URL") || "https://openaperture-mgr.host.co",
	oauth_login_url: System.get_env("OAUTH_LOGIN_URL") || "https://auth.host.co",
	oauth_client_id: System.get_env("OAUTH_CLIENT_ID") ||"id",
	oauth_client_secret: System.get_env("OAUTH_CLIENT_SECRET") || "secret"

config :openaperture_overseer, 
	exchange_id: "1",
	broker_id: "1"

config :openaperture_overseer_api,
	module_type: :test,
	autostart: false,	
	exchange_id: "1",
	broker_id: "1"