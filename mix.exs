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
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:test]},
      {:markdown, github: "devinus/markdown", only: [:test]},

      {:poison, "~> 1.3.1"},
      {:timex, "~> 0.13.3"},
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "c5d30b43ebf64f93b833e4fff83e0c92466cb035", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "5d442cfbdd45e71c1101334e185d02baec3ef945", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "4d65d2295f2730bc74ec695c32fa0d2478158182", override: true},
        
      #test dependencies
      {:exvcr, github: "parroty/exvcr", override: true},
      {:meck, "0.8.2", override: true}      
    ]
  end
end
