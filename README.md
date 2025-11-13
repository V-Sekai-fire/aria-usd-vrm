# AriaUsdVrm

VRM to USD conversion package for Elixir.

## Overview

This package provides VRM (VR avatar format) to USD conversion functionality. It depends on `aria_usd` for core USD operations.

## Installation

Add `aria_usd_vrm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:aria_usd_vrm, path: "../apps/aria_usd_vrm"},
    {:aria_usd, git: "https://github.com/V-Sekai-fire/aria-usd.git"}
  ]
end
```

## Usage

```elixir
# Convert VRM to USD
AriaUsdVrm.vrm_to_usd("model.vrm", "output.usd",
  vrm_extensions: extensions,
  vrm_metadata: metadata
)
```

## VRM Schema Plugin

This package includes a USD schema plugin for preserving VRM-specific data in USD files. The plugin is located at `priv/plugins/dcc_mcp_vrm/` and provides the `VrmAPI` schema for storing VRM extensions and metadata.

## Requirements

- Elixir ~> 1.18
- `aria_usd` package
- USD Python bindings (pxr)

## License

MIT

