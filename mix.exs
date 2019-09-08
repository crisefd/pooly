defmodule Pooly.MixProject do
  use Mix.Project

  def project do
    [
      app: :pooly,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
		#	build_embedded: Mix.env() === :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
			mod: {Pooly, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
		[{:observer_cli, "~> 1.5"}]
  end
end
