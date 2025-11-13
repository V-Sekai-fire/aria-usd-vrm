# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaUsdVrm.MixProject do
  use Mix.Project

  def project do
    [
      app: :aria_usd_vrm,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:aria_usd, git: "https://github.com/V-Sekai-fire/aria-usd.git", branch: "feature/mesh-and-variant-support"},
      {:jason, "~> 1.4"},
      {:pythonx, "~> 0.4.0", runtime: false}
    ]
  end
end

