# DCC MCP VRM USD Schema

This directory contains a USD schema plugin for preserving VRM-specific data in USD files.

## Overview

The `VrmAPI` schema is a codeless API schema that can be applied to USD prims to store VRM-specific extensions and metadata. This enables round-trip conversion between VRM and USD formats while preserving VRM-specific features.

## Schema Definition

The schema is defined in `schema/schema.usda` and provides the following attributes:

- `vrm:version` - VRM format version (0.0 or 1.0)
- `vrm:extensions` - VRM extensions data as JSON string (extensions.VRM or extensions.VRMC_vrm)
- `vrm:metadata` - VRM metadata as JSON string (title, author, humanoid bones, expressions, etc.)
- `vrm:sourceFormat` - Source format indicator (default: "VRM")

## Usage

### Applying the Schema

The schema is automatically applied when converting VRM to USD using `AriaUsd.vrm_to_usd/2`. The schema is applied to the root prim of the USD stage.

### Reading VRM Data from USD

To read VRM data back from a USD file:

```python
from pxr import Usd, Sdf

stage = Usd.Stage.Open("model.usd")
root_prim = stage.GetPseudoRoot()

# Check if VrmAPI is applied
api_schemas = root_prim.GetMetadata('apiSchemas')
has_vrm = 'VrmAPI' in (api_schemas if api_schemas else [])

if has_vrm:
    # Read VRM attributes
    version_attr = root_prim.GetAttribute('vrm:version')
    ext_attr = root_prim.GetAttribute('vrm:extensions')
    meta_attr = root_prim.GetAttribute('vrm:metadata')

    if version_attr and ext_attr and meta_attr:
        version = version_attr.Get()
        extensions_json = ext_attr.Get()
        metadata_json = meta_attr.Get()

        # Parse JSON strings
        import json
        extensions = json.loads(extensions_json)
        metadata = json.loads(metadata_json)
```

## Installation

The schema plugin is automatically available when the `priv/plugins/dcc_mcp_vrm` directory is in USD's plugin search path. To use it:

1. Add the plugin directory to `PXR_PLUGINPATH_NAME` environment variable, or
2. Place the plugin in USD's standard plugin search locations

## Schema Structure

```
priv/plugins/dcc_mcp_vrm/
├── plugInfo.json          # Plugin registration
└── schema/
    └── schema.usda        # Schema definition
```

## References

- USD Schema Documentation: https://openusd.org/dev/wp_schema_versioning.html
- USD Survival Guide - Schemas: https://lucascheller.github.io/VFX-UsdSurvivalGuide/pages/core/plugins/schemas.html
