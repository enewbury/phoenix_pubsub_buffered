defmodule PhoenixPubSubBuffered.MixProject do
  use Mix.Project

  @source_url "https://github.com/enewbury/phoenix_pubsub_buffered"
  @version "0.1.0"

  def project do
    [
      app: :phoenix_pubsub_buffered,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      # Docs
      name: "PhoenixPubSubBuffered",
      description: "A :pg based Phoenix PubSub adapter with at-least-once delivery",
      source_url: @source_url,
      docs: [
        # The main page in the docs
        main: "PhoenixPubSubBuffered",
        extras: ["README.md", "CHANGELOG.md", "LICENSE"],
        source_ref: "v#{@version}"
      ],
      package: [
        maintainers: ["Eric Newbury"],
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url}
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_pubsub, "~> 2.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
