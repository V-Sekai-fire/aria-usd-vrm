# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaUsdVrm.Parser do
  @moduledoc """
  VRM file parser using aria-gltf for GLTF parsing and custom VRM extension handling.

  This module provides native Elixir parsing of VRM files, extracting both GLTF data
  and VRM-specific extensions (VRM 0.0 and VRMC_vrm 1.0).

  ## VRM File Structure

  VRM files are GLB (binary GLTF) files with:
  - GLB binary format containing JSON chunk and binary chunk
  - VRM-specific extensions in GLTF JSON:
    - VRM 0.0: `extensions.VRM`
    - VRM 1.0: `extensions.VRMC_vrm`

  ## aria-gltf Integration

  This module uses `AriaGltf.Import.from_file/2` to parse GLTF files, providing
  structured access to nodes, meshes, materials, textures, and other GLTF data.
  The focus is on strengthening aria-gltf VRM parsing rather than creating fallbacks.

  ## Usage

      # Parse complete VRM file
      {:ok, vrm_data} = AriaUsdVrm.Parser.parse_vrm("path/to/model.vrm")
      # Returns: %{
      #   gltf: gltf_data,
      #   vrm_extensions: vrm_extensions,
      #   metadata: metadata,
      #   version: "0.0" | "1.0"
      # }

      # Extract GLTF only
      {:ok, gltf_data} = AriaUsdVrm.Parser.extract_gltf("path/to/model.vrm")

      # Extract to temp directory (for USD conversion)
      {:ok, tmpdir, gltf_path} = AriaUsdVrm.Parser.extract_to_temp("path/to/model.vrm")
      # Use gltf_path for USD conversion, then clean up:
      File.rm_rf(tmpdir)

  ## VRM Metadata Extraction

  The parser extracts the following VRM-specific metadata:
  - **VRM 0.0**: meta, humanoid bones, blendShapeMaster (expressions), firstPerson, secondaryAnimation, materialProperties
  - **VRM 1.0**: meta, humanoid bones, expressions, lookAt, springBone, materialProperties

  ## Error Handling

  If aria-gltf parsing fails, detailed error logging is used to diagnose issues.
  The focus is on strengthening aria-gltf rather than creating fallbacks.
  """

  require Logger

  alias AriaGltf.Import
  alias AriaGltf.Import.BinaryLoader
  alias Jason

  @type vrm_result ::
          {:ok, map()}
          | {:error, String.t()}

  @type vrm_data :: %{
          gltf: map(),
          vrm_extensions: map(),
          metadata: map(),
          version: String.t()
        }

  @doc """
  Parses a VRM file and returns structured data including GLTF and VRM extensions.

  ## Parameters
    - vrm_path: Path to VRM file

  ## Returns
    - `{:ok, vrm_data}` - Success with parsed VRM data
    - `{:error, reason}` - Error message

  ## Example

      {:ok, data} = parse_vrm("model.vrm")
      # data contains: gltf, vrm_extensions, metadata, version
  """
  @spec parse_vrm(String.t()) :: vrm_result()
  def parse_vrm(vrm_path) when is_binary(vrm_path) do
    Logger.info("🔍 Starting VRM parse for: #{vrm_path}")
    Logger.info("📁 File exists: #{File.exists?(vrm_path)}")

    if File.exists?(vrm_path) do
      file_size = File.stat!(vrm_path).size
      Logger.info("📊 File size: #{file_size} bytes")
    end

    with {:ok, gltf_json} <- load_gltf_json_from_glb(vrm_path) do
      Logger.info("✅ GLB JSON chunk extracted (#{map_size(gltf_json)} top-level keys)")

      with {:ok, gltf_data} <- parse_gltf_with_aria(vrm_path, []) do
        Logger.info("✅ GLTF parsed with aria-gltf")
        Logger.info("   - Nodes: #{length(Map.get(gltf_data, :nodes, []))}")
        Logger.info("   - Meshes: #{length(Map.get(gltf_data, :meshes, []))}")
        Logger.info("   - Materials: #{length(Map.get(gltf_data, :materials, []))}")

        with {:ok, vrm_extensions} <- parse_vrm_extensions(gltf_json) do
          Logger.info("✅ VRM extensions parsed")
          Logger.info("   - Extension keys: #{inspect(Map.keys(vrm_extensions))}")

          metadata = extract_vrm_metadata(vrm_extensions, gltf_json)
          version = detect_vrm_version(gltf_json)

          Logger.info("✅ VRM metadata extracted")
          Logger.info("   - Version: #{version}")
          Logger.info("   - Metadata keys: #{inspect(Map.keys(metadata))}")

          # Print detailed metadata
          if Map.has_key?(metadata, :humanoid_bones) do
            bones = metadata.humanoid_bones
            Logger.info("   - Humanoid bones: #{length(bones)} bones")

            if length(bones) > 0 do
              Logger.info("     Sample bones: #{inspect(Enum.take(bones, 5))}")
            end
          end

          if Map.has_key?(metadata, :blend_shapes) do
            blend_shapes = metadata.blend_shapes
            Logger.info("   - Blend shapes: #{length(blend_shapes)} shapes")
          end

          if Map.has_key?(metadata, :expressions) do
            expressions = metadata.expressions
            Logger.info("   - Expressions: #{length(expressions)} expressions")
          end

          result = %{
            gltf: gltf_data,
            vrm_extensions: vrm_extensions,
            metadata: metadata,
            version: version
          }

          Logger.info("✅ VRM parse complete!")
          {:ok, result}
        else
          {:error, reason} ->
            Logger.error("❌ Failed to parse VRM extensions: #{reason}")
            {:error, reason}
        end
      else
        {:error, reason} ->
          Logger.error("❌ Failed to parse GLTF with aria-gltf: #{reason}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("❌ Failed to load GLB JSON chunk: #{reason}")
        {:error, reason}

      error ->
        Logger.error("❌ Unexpected error: #{inspect(error)}")
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end

  @doc """
  Extracts GLTF data from VRM file without parsing VRM extensions.

  ## Parameters
    - vrm_path: Path to VRM file

  ## Returns
    - `{:ok, gltf_data}` - Success with GLTF data
    - `{:error, reason}` - Error message
  """
  @spec extract_gltf(String.t()) :: {:ok, map()} | {:error, String.t()}
  def extract_gltf(vrm_path) when is_binary(vrm_path) do
    case parse_gltf_with_aria(vrm_path, []) do
      {:ok, gltf_data} -> {:ok, gltf_data}
      error -> error
    end
  end

  @doc """
  Reads VRM data from a USD file that was converted from VRM.

  This function reads the VrmAPI schema attributes from USD to retrieve
  VRM extensions and metadata that were preserved during conversion.

  **Note**: This function requires Pythonx to be available for USD operations.

  ## Parameters
    - usd_path: Path to USD file

  ## Returns
    - `{:ok, vrm_data}` - Success with VRM data (extensions and metadata)
    - `{:error, reason}` - Error message (e.g., if USD doesn't contain VRM data)

  ## Example

      {:ok, data} = read_vrm_from_usd("model.usd")
      # data contains: %{
      #   version: "0.0" | "1.0",
      #   vrm_extensions: %{...},
      #   metadata: %{...},
      #   has_vrm_data: true
      # }
  """
  @spec read_vrm_from_usd(String.t()) :: vrm_result()
  def read_vrm_from_usd(usd_path) when is_binary(usd_path) do
    case File.exists?(usd_path) do
      false ->
        {:error, "USD file not found: #{usd_path}"

      true ->
        # Use Pythonx directly for USD operations
        read_vrm_schema_from_usd(usd_path)
    end
  end

  defp read_vrm_schema_from_usd(usd_path) do
    alias Pythonx

    code = """
    import os
    import json
    from pxr import Usd

    usd_path = '#{usd_path}'

    if not os.path.exists(usd_path):
        raise FileNotFoundError(f"USD file not found: {usd_path}")

    stage = Usd.Stage.Open(usd_path)
    if not stage:
        raise ValueError("Failed to open USD stage")

    root_prim = stage.GetPseudoRoot()

    # Check if VrmAPI is applied
    api_schemas = root_prim.GetMetadata('apiSchemas')
    has_vrm = api_schemas and 'VrmAPI' in (list(api_schemas) if isinstance(api_schemas, (list, tuple)) else [api_schemas])

    if not has_vrm:
        result = {"error": "USD file does not contain VRM schema data"}
    else:
        # Read VRM attributes
        version_attr = root_prim.GetAttribute('vrm:version')
        ext_attr = root_prim.GetAttribute('vrm:extensions')
        meta_attr = root_prim.GetAttribute('vrm:metadata')
        
        if version_attr and ext_attr and meta_attr:
            version = version_attr.Get()
            extensions_json = ext_attr.Get()
            metadata_json = meta_attr.Get()
            
            # Parse JSON strings
            try:
                extensions = json.loads(extensions_json) if extensions_json else {}
                metadata = json.loads(metadata_json) if metadata_json else {}
                
                result = {
                    "version": version,
                    "extensions": extensions,
                    "metadata": metadata,
                    "has_vrm_data": True
                }
            except json.JSONDecodeError as e:
                result = {"error": f"Failed to parse VRM JSON data: {str(e)}"}
        else:
            result = {"error": "VRM schema attributes not found on root prim"}

    json.dumps(result)
    """

    case Pythonx.eval(code, %{}) do
      {result, _globals} ->
        case Pythonx.decode(result) do
          json_str when is_binary(json_str) ->
            case Jason.decode(json_str) do
              {:ok, %{"error" => error_msg}} ->
                {:error, error_msg}

              {:ok, data} when is_map(data) ->
                # Convert string keys to atoms where appropriate
                vrm_data = %{
                  version: data["version"] || "unknown",
                  vrm_extensions: data["extensions"] || %{},
                  metadata: data["metadata"] || %{},
                  has_vrm_data: data["has_vrm_data"] || false
                }

                {:ok, vrm_data}

              {:ok, _} ->
                {:error, "Unexpected data format from USD"}
            end

          _ ->
            {:error, "Failed to decode read_vrm_from_usd result"}
        end

      error ->
        {:error, inspect(error)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # GLB File Handling

  defp load_gltf_json_from_glb(glb_path) do
    case File.read(glb_path) do
      {:ok, data} ->
        # Use aria-gltf BinaryLoader to parse GLB
        # Returns {json_chunk, [bin_chunks]} - GLB can have multiple binary chunks
        case BinaryLoader.parse_glb(data) do
          {:ok, {json_data, _bin_chunks}} ->
            case Jason.decode(json_data) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, "Failed to parse GLB JSON: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to read GLB file: #{inspect(reason)}"}
    end
  end

  @doc """
  Extracts VRM to a temporary directory and returns the directory path.
  Useful for operations that need to preserve extracted files (e.g., USD conversion).

  ## Parameters
    - vrm_path: Path to VRM file

  ## Returns
    - `{:ok, tmpdir, gltf_path}` - Success with temp directory and GLTF path
    - `{:error, reason}` - Error message

  ## Note
    The caller is responsible for cleaning up the temp directory after use.
  """
  @spec extract_to_temp(String.t()) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  def extract_to_temp(vrm_path) when is_binary(vrm_path) do
    case File.exists?(vrm_path) do
      false ->
        {:error, "VRM file not found: #{vrm_path}"

      true ->
        # Copy GLB file to temporary directory
        tmpdir = System.tmp_dir!() |> Path.join("vrm_extract_#{:rand.uniform(1_000_000)}")
        File.mkdir_p!(tmpdir)

        gltf_filename = Path.basename(vrm_path)
        gltf_path = Path.join(tmpdir, gltf_filename)

        case File.copy(vrm_path, gltf_path) do
          {:ok, _bytes_copied} ->
            {:ok, tmpdir, gltf_path}

          {:error, reason} ->
            File.rm_rf(tmpdir)
            {:error, "Failed to copy VRM GLB file: #{inspect(reason)}"}
        end
    end
  end

  # GLTF Parsing

  defp parse_gltf_with_aria(gltf_path, _buffers) do
    # Pre-validate GLB structure before attempting aria-gltf parsing
    case validate_glb_structure(gltf_path) do
      :ok ->
        parse_gltf_with_aria_attempt(gltf_path)

      {:error, reason} ->
        Logger.error("❌ GLB pre-validation failed: #{reason}")
        Logger.error("   File: #{gltf_path}")
        {:error, "GLB validation failed: #{reason}"}
    end
  end

  # Attempt aria-gltf parsing with different parameter combinations
  defp parse_gltf_with_aria_attempt(gltf_path) do
    # Try different parameter combinations for better VRM compatibility
    attempts = [
      # Primary attempt: standard parameters
      {[validate: false, load_buffers: true, load_images: false], "standard"},
      # Fallback 1: without loading buffers (may help with some edge cases)
      {[validate: false, load_buffers: false, load_images: false], "no_buffers"},
      # Fallback 2: with validation enabled (may catch issues early)
      {[validate: true, load_buffers: true, load_images: false], "with_validation"}
    ]

    attempt_parse_with_retries(gltf_path, attempts)
  end

  defp attempt_parse_with_retries(gltf_path, [attempt | rest]) do
    {params, attempt_name} = attempt

    Logger.debug("🔍 Attempting aria-gltf parse (#{attempt_name}): #{inspect(params)}")

    case Import.from_file(gltf_path, params) do
      {:ok, document} when is_map(document) ->
        Logger.info("✅ aria-gltf parse succeeded with #{attempt_name} parameters")
        extract_gltf_data_from_document(document)

      {:error, reason} ->
        Logger.warning("⚠️ aria-gltf parse failed with #{attempt_name}: #{inspect(reason)}")

        if rest != [] do
          Logger.info("🔄 Retrying with different parameters...")
          attempt_parse_with_retries(gltf_path, rest)
        else
          # All attempts failed - log detailed error and fallback
          log_detailed_aria_error(gltf_path, reason)
          fallback_to_json_parsing(gltf_path, reason)
        end
    end
  end

  defp attempt_parse_with_retries(_gltf_path, []) do
    {:error, "All aria-gltf parse attempts failed"}
  end

  # Extract structured GLTF data from aria-gltf document
  defp extract_gltf_data_from_document(document) do
    # Ensure extensions are properly extracted from document
    extensions = extract_extensions_from_document(document)

    gltf_data = %{
      document: document,
      nodes: Map.get(document, :nodes) || [],
      meshes: Map.get(document, :meshes) || [],
      materials: Map.get(document, :materials) || [],
      textures: Map.get(document, :textures) || [],
      images: Map.get(document, :images) || [],
      buffers: Map.get(document, :buffers) || [],
      scenes: Map.get(document, :scenes) || [],
      animations: Map.get(document, :animations) || [],
      extensions: extensions
    }

    Logger.debug("📊 Extracted GLTF data: #{map_size(gltf_data)} top-level keys")
    Logger.debug("   Extensions: #{inspect(Map.keys(extensions))}")

    {:ok, gltf_data}
  end

  # Extract extensions from aria-gltf document
  # aria-gltf may store extensions in different locations, so we check multiple places
  defp extract_extensions_from_document(document) do
    # Check direct extensions key
    direct_extensions = Map.get(document, :extensions) || %{}

    # Check for extensions in root-level keys (some aria-gltf versions may store them differently)
    root_extensions =
      document
      |> Map.keys()
      |> Enum.filter(fn key ->
        key_string = to_string(key)
        String.contains?(key_string, "extension") or String.contains?(key_string, "VRM")
      end)
      |> Enum.reduce(%{}, fn key, acc ->
        case Map.get(document, key) do
          nil -> acc
          value when is_map(value) -> Map.merge(acc, value)
          _ -> acc
        end
      end)

    # Merge both sources
    Map.merge(direct_extensions, root_extensions)
  end

  # Log detailed error information for diagnosis
  defp log_detailed_aria_error(gltf_path, reason) do
    Logger.error("❌ aria-gltf parsing failed for: #{gltf_path}")
    Logger.error("   Error: #{inspect(reason)}")

    # Try to get file information for diagnostics
    case File.stat(gltf_path) do
      {:ok, stat} ->
        Logger.error("   File size: #{stat.size} bytes")
        Logger.error("   File type: #{stat.type}")

      {:error, stat_error} ->
        Logger.error("   Could not stat file: #{inspect(stat_error)}")
    end

    # Try to validate GLB structure again for additional diagnostics
    case validate_glb_structure(gltf_path) do
      :ok ->
        Logger.error("   GLB structure validation: ✅ passed")

      {:error, validation_error} ->
        Logger.error("   GLB structure validation: ❌ failed - #{validation_error}")
    end
  end

  # Fallback to basic JSON parsing if aria-gltf fails
  defp fallback_to_json_parsing(gltf_path, aria_error) do
    Logger.warning("⚠️ Falling back to basic JSON parsing")
    Logger.warning("   This is a degraded mode - VRM extensions may not be fully parsed")

    case load_gltf_json_from_glb(gltf_path) do
      {:ok, json} ->
        Logger.info("✅ Basic JSON parsing succeeded")
        {:ok,
         %{
           json: json,
           nodes: json["nodes"] || [],
           meshes: json["meshes"] || [],
           materials: json["materials"] || [],
           textures: json["textures"] || [],
           images: json["images"] || [],
           buffers: json["buffers"] || [],
           # Note: extensions may not be fully parsed in fallback mode
           extensions: json["extensions"] || %{}
         }}

      error ->
        Logger.error("❌ Fallback JSON parsing also failed")
        {:error, "Both aria-gltf and JSON parsing failed. aria-gltf error: #{inspect(aria_error)}"}
    end
  end

  # Pre-validate GLB file structure
  # Checks GLB magic number, version, and basic structure before attempting full parse
  defp validate_glb_structure(glb_path) do
    case File.read(glb_path) do
      {:ok, data} ->
        validate_glb_data(data)

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  # Validate GLB binary data structure
  # GLB format: 12-byte header (magic, version, length) + chunks
  defp validate_glb_data(data) when byte_size(data) < 12 do
    {:error, "File too short to be a valid GLB (minimum 12 bytes for header)"}
  end

  defp validate_glb_data(data) do
    # Check GLB magic number (0x46546C67 = "glTF" in ASCII)
    <<magic::little-32, version::little-32, length::little-32, rest::binary>> = data

    if magic != 0x46546C67 do
      {:error, "Invalid GLB magic number: expected 0x46546C67 (glTF), got 0x#{Integer.to_string(magic, 16)}"}
    elsif version != 2 do
      {:error, "Unsupported GLB version: expected 2, got #{version}"}
    elsif length != byte_size(data) do
      {:error, "GLB length mismatch: header says #{length} bytes, file is #{byte_size(data)} bytes"}
    elsif byte_size(rest) < 8 do
      {:error, "GLB too short: no room for first chunk header (need 8 bytes)"}
    else
      # Validate first chunk (must be JSON chunk: 0x4E4F534A)
      <<chunk_length::little-32, chunk_type::little-32, _chunk_data::binary>> = rest

      if chunk_type != 0x4E4F534A do
        {:error, "Invalid first chunk type: expected 0x4E4F534A (JSON), got 0x#{Integer.to_string(chunk_type, 16)}"}
      else
        :ok
      end
    end
  rescue
    MatchError ->
      {:error, "Failed to parse GLB header structure"}
    e ->
      {:error, "GLB validation error: #{Exception.message(e)}"}
  end

  # VRM Extension Parsing

  defp parse_vrm_extensions(gltf_json) do
    extensions = gltf_json["extensions"] || %{}

    cond do
      Map.has_key?(extensions, "VRM") ->
        {:ok, %{version: "0.0", extension: parse_vrm_0_0_extension(extensions["VRM"])}}

      Map.has_key?(extensions, "VRMC_vrm") ->
        {:ok, %{version: "1.0", extension: parse_vrm_1_0_extension(extensions["VRMC_vrm"])}}

      true ->
        {:error, "No VRM extensions found in GLTF"}
    end
  end

  defp parse_vrm_0_0_extension(vrm_ext) when is_map(vrm_ext) do
    %{
      meta: vrm_ext["meta"] || %{},
      humanoid: vrm_ext["humanoid"] || %{},
      firstPerson: vrm_ext["firstPerson"] || %{},
      blendShapeMaster: vrm_ext["blendShapeMaster"] || %{},
      secondaryAnimation: vrm_ext["secondaryAnimation"] || %{},
      materialProperties: vrm_ext["materialProperties"] || []
    }
  end

  defp parse_vrm_1_0_extension(vrmc_ext) when is_map(vrmc_ext) do
    %{
      specVersion: vrmc_ext["specVersion"] || "1.0",
      meta: vrmc_ext["meta"] || %{},
      humanoid: vrmc_ext["humanoid"] || %{},
      firstPerson: vrmc_ext["firstPerson"] || %{},
      expressions: vrmc_ext["expressions"] || %{},
      lookAt: vrmc_ext["lookAt"] || %{},
      springBone: vrmc_ext["springBone"] || %{},
      materialProperties: vrmc_ext["materialProperties"] || []
    }
  end

  defp extract_vrm_metadata(vrm_extensions, gltf_json) do
    extension_data = vrm_extensions.extension

    base_metadata = %{
      format: "VRM",
      version: vrm_extensions.version,
      gltf_version: gltf_json["asset"]["version"] || "unknown"
    }

    case vrm_extensions.version do
      "0.0" ->
        Map.merge(base_metadata, %{
          title: get_in(extension_data, [:meta, "title"]),
          author: get_in(extension_data, [:meta, "author"]),
          allowedUserName: get_in(extension_data, [:meta, "allowedUserName"]),
          violentUssageName: get_in(extension_data, [:meta, "violentUssageName"]),
          sexualUssageName: get_in(extension_data, [:meta, "sexualUssageName"]),
          commercialUssageName: get_in(extension_data, [:meta, "commercialUssageName"]),
          humanoid_bones: extract_humanoid_bones(extension_data.humanoid),
          blend_shapes: extract_blend_shapes(extension_data.blendShapeMaster),
          expressions: extract_expressions_vrm_0_0(extension_data.blendShapeMaster)
        })

      "1.0" ->
        authors = get_in(extension_data, [:meta, "authors"]) || []
        author_name = if length(authors) > 0, do: hd(authors)["name"], else: nil

        Map.merge(base_metadata, %{
          title: get_in(extension_data, [:meta, "title"]),
          author: author_name,
          humanoid_bones: extract_humanoid_bones_vrm_1_0(extension_data.humanoid),
          expressions: extract_expressions_vrm_1_0(extension_data.expressions)
        })

      _ ->
        base_metadata
    end
  end

  defp extract_humanoid_bones(humanoid) when is_map(humanoid) do
    humanoid["humanBones"] || %{}
  end

  defp extract_humanoid_bones_vrm_1_0(humanoid) when is_map(humanoid) do
    humanoid["humanBones"] || %{}
  end

  defp extract_blend_shapes(blend_shape_master) when is_map(blend_shape_master) do
    blend_shape_master["blendShapeGroups"] || []
  end

  defp extract_expressions_vrm_0_0(blend_shape_master) when is_map(blend_shape_master) do
    blend_shape_master["blendShapeGroups"] || []
  end

  defp extract_expressions_vrm_1_0(expressions) when is_map(expressions) do
    expressions["preset"] || %{}
  end

  defp detect_vrm_version(gltf_json) do
    extensions = gltf_json["extensions"] || %{}

    cond do
      Map.has_key?(extensions, "VRMC_vrm") -> "1.0"
      Map.has_key?(extensions, "VRM") -> "0.0"
      true -> "unknown"
    end
  end
end

