# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaUsdVrm do
  @moduledoc """
  VRM to USD conversion operations.
  """

  alias AriaUsd
  alias Pythonx
  alias Jason

  @type usd_result :: {:ok, term()} | {:error, String.t()}

  @doc """
  Converts VRM to USD (one-way, transmission format to internal format).

  ## Parameters
    - vrm_path: Path to VRM file
    - output_usd_path: Path to output USD file
    - opts: Optional keyword list with :vrm_extensions and :vrm_metadata for preserving VRM data

  ## Returns
    - `{:ok, String.t()}` - Success message
    - `{:error, String.t()}` - Error message
  """
  @spec vrm_to_usd(String.t(), String.t(), keyword()) :: usd_result()
  def vrm_to_usd(vrm_path, output_usd_path, opts \\ [])
      when is_binary(vrm_path) and is_binary(output_usd_path) do
    vrm_extensions = Keyword.get(opts, :vrm_extensions)
    vrm_metadata = Keyword.get(opts, :vrm_metadata)

    if vrm_extensions && vrm_metadata do
      # Use provided VRM data for conversion
      case AriaUsd.ensure_pythonx() do
        :ok ->
          # Extract GLTF from VRM first (simplified - assumes VRM is GLB)
          do_vrm_to_usd_with_metadata(vrm_path, output_usd_path, vrm_extensions, vrm_metadata)

        :mock ->
          mock_vrm_to_usd(vrm_path, output_usd_path)
      end
    else
      # Fallback to Python implementation without metadata preservation
      case AriaUsd.ensure_pythonx() do
        :ok -> do_vrm_to_usd(vrm_path, output_usd_path)
        :mock -> mock_vrm_to_usd(vrm_path, output_usd_path)
      end
    end
  end

  defp do_vrm_to_usd_with_metadata(gltf_path, output_usd_path, vrm_extensions, vrm_metadata) do
    # Encode VRM extensions and metadata as JSON for storage in USD
    # Use base64 encoding to avoid string escaping issues in Python
    vrm_ext_json = Jason.encode!(vrm_extensions) |> Base.encode64()
    vrm_meta_json = Jason.encode!(vrm_metadata) |> Base.encode64()
    # Metadata uses atom keys, so access with atom
    vrm_version = Map.get(vrm_metadata, :version, "unknown") || "unknown"

    code = """
    import os
    import json
    import base64
    from pxr import Usd, Sdf, Vt

    gltf_path = '#{gltf_path}'
    output_usd_path = '#{output_usd_path}'
    vrm_ext_json_b64 = '#{vrm_ext_json}'
    vrm_meta_json_b64 = '#{vrm_meta_json}'
    vrm_version = '#{vrm_version}'

    if not os.path.exists(gltf_path):
        raise FileNotFoundError(f"GLTF file not found: {gltf_path}")

    # Decode base64 JSON strings
    try:
        vrm_ext_json = base64.b64decode(vrm_ext_json_b64).decode('utf-8')
        vrm_meta_json = base64.b64decode(vrm_meta_json_b64).decode('utf-8')
    except Exception as e:
        raise ValueError(f"Failed to decode VRM JSON data: {str(e)}")

    # Use USD to open GLTF (via Adobe plugins if available)
    stage = Usd.Stage.Open(gltf_path)
    if stage:
        # Get root prim (or create one if needed)
        root_prim = stage.GetPseudoRoot()
        
        # Apply VrmAPI schema using apiSchemas metadata
        # Handle different USD types for apiSchemas (VtArray, list, etc.)
        api_schemas = root_prim.GetMetadata('apiSchemas')
        api_schemas_list = []
        
        if api_schemas:
            # Convert VtArray or other USD types to Python list
            if hasattr(api_schemas, '__iter__') and not isinstance(api_schemas, (str, bytes)):
                api_schemas_list = [str(schema) for schema in api_schemas]
            elif isinstance(api_schemas, (list, tuple)):
                api_schemas_list = [str(s) for s in api_schemas]
            else:
                api_schemas_list = [str(api_schemas)]
        
        # Add VrmAPI to apiSchemas if not already present
        if 'VrmAPI' not in api_schemas_list:
            api_schemas_list.append('VrmAPI')
            # Set as VtArray for proper USD type
            root_prim.SetMetadata('apiSchemas', Vt.StringArray(api_schemas_list))
        
        # Create VrmAPI attributes on root prim
        # vrm:version
        version_attr = root_prim.CreateAttribute('vrm:version', Sdf.ValueTypeNames.String, True)
        version_attr.Set(vrm_version)
        
        # vrm:extensions (as JSON string)
        ext_attr = root_prim.CreateAttribute('vrm:extensions', Sdf.ValueTypeNames.String, True)
        ext_attr.Set(vrm_ext_json)
        
        # vrm:metadata (as JSON string)
        meta_attr = root_prim.CreateAttribute('vrm:metadata', Sdf.ValueTypeNames.String, True)
        meta_attr.Set(vrm_meta_json)
        
        # vrm:sourceFormat
        source_attr = root_prim.CreateAttribute('vrm:sourceFormat', Sdf.ValueTypeNames.String, True)
        source_attr.Set('VRM')
        
        stage.Export(output_usd_path)
        result = f"Converted GLTF {gltf_path} to USD {output_usd_path} with VRM schema applied"
    else:
        result = "Failed to open GLTF file"

    result
    """

    case Pythonx.eval(code, %{}) do
      {result, _globals} ->
        case Pythonx.decode(result) do
          status when is_binary(status) -> {:ok, status}
          _ -> {:error, "Failed to decode vrm_to_usd result"}
        end

      error ->
        {:error, inspect(error)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp mock_vrm_to_usd(vrm_path, output_usd_path) do
    # Check if VRM file exists
    if File.exists?(vrm_path) do
      {:ok, "Mock converted VRM #{vrm_path} to USD #{output_usd_path}"}
    else
      {:error, "VRM file not found: #{vrm_path}"}
    end
  end

  defp do_vrm_to_usd(vrm_path, output_usd_path) do
    code = """
    import os
    from pxr import Usd

    vrm_path = '#{vrm_path}'
    output_usd_path = '#{output_usd_path}'

    if not os.path.exists(vrm_path):
        raise FileNotFoundError(f"VRM file not found: {vrm_path}")

    # VRM files are GLB format, use directly with USD GLTF plugin
    gltf_path = vrm_path

    # Use USD to open GLTF (via Adobe plugins if available)
    stage = Usd.Stage.Open(gltf_path)
    if stage:
        stage.Export(output_usd_path)
        result = f"Converted VRM {vrm_path} to USD {output_usd_path}"
    else:
        result = "Failed to open GLTF from VRM"

    result
    """

    case Pythonx.eval(code, %{}) do
      {result, _globals} ->
        case Pythonx.decode(result) do
          status when is_binary(status) -> {:ok, status}
          _ -> {:error, "Failed to decode vrm_to_usd result"}
        end

      error ->
        {:error, inspect(error)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
