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
      applications: 
      [
        :logger, 
        :openaperture_messaging, 
        :openaperture_manager_api, 
        :openaperture_overseer_api
      ]
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
      {:ex_doc, "0.7.3", only: :test},
      {:earmark, "0.1.17", only: :test},

      {:poison, "~> 1.4.0", override: true},
      {:timex, "~> 0.13.3", override: true},
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "e48c52b98abc86f4404954e7b4c85b090e83c69c", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "b9542dde7da3c892af569c4fc3f7f00e4f94cf55", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "6993e014773e2c16e379eb85a77f3faaa273d0e1", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "9104035464efda2fadb2eec0297ca9cb2495158f", override: true},
      {:timex_extensions, git: "https://github.com/OpenAperture/timex_extensions.git", ref: "1665c1df90397702daf492c6f940e644085016cd", override: true},
  
      #test dependencies
      {:exvcr, github: "parroty/exvcr", override: true},
      {:meck, "0.8.2", override: true},
      {:httpoison, "0.7.0", override: true}      
    ]
  end
end
