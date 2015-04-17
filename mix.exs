defmodule OpenAperture.Overseer.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_overseer,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: { OpenAperture.Overseer, [] },
      applications: [:logger, :openaperture_messaging, :openaperture_manager_api, :openaperture_overseer_api]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:ex_doc, github: "elixir-lang/ex_doc"},
      {:markdown, github: "devinus/markdown"},

      {:poison, "~> 1.3.1"},
      {:timex, "~> 0.13.3"},
      {:openaperture_messaging, git: "https://#{System.get_env("GITHUB_OAUTH_TOKEN")}:x-oauth-basic@github.com/OpenAperture/messaging.git", 
        ref: "671d48c1eb385747b57c41edda2065c9bb8171ba", override: true},
      {:openaperture_manager_api, git: "https://#{System.get_env("GITHUB_OAUTH_TOKEN")}:x-oauth-basic@github.com/OpenAperture/manager_api.git", 
        ref: "7698785f22fb5084671882e4bf14a8824804d53a", override: true},
      {:openaperture_overseer_api, git: "https://#{System.get_env("GITHUB_OAUTH_TOKEN")}:x-oauth-basic@github.com/OpenAperture/overseer_api.git", 
        ref: "3aeab7db575bde674ab364fefdf69721c67c5d46", override: true},
        
      #test dependencies
      {:exvcr, github: "parroty/exvcr", override: true},
      {:meck, "0.8.2", override: true}      
    ]
  end
end
