defmodule Contentful.Delivery do
  @moduledoc """
  A HTTP client for Contentful.
  This module contains the functions to interact with Contentful's read-only
  Content Delivery API.
  """

  require Logger
  use HTTPoison.Base

  @endpoint "cdn.contentful.com"
  @protocol "https"

  def space(space_id, access_token) do
    space_url = "/spaces/#{space_id}"

    contentful_request(
      space_url,
      access_token
    )
  end

   def entries(space_id, access_token, params \\ %{}) do
    entries_url = "/spaces/#{space_id}/entries"

    response = contentful_request(
      entries_url,
      access_token,
      params
    ) |> resolve_includes

    response["items"]
    |> IO.inspect
  end

  def entry(space_id, access_token, entry_id, params \\ %{}) do
    {:ok, entry} = entries(space_id, access_token, Map.merge(params, %{'sys.id' => entry_id}))
    |> Enum.fetch(0)

    entry
  end

  def assets(space_id, access_token, params \\ %{}) do
    assets_url = "/spaces/#{space_id}/assets"

    contentful_request(
      assets_url,
      access_token,
      params
    )["items"]
  end

  def asset(space_id, access_token, asset_id, params \\ %{}) do
    asset_url = "/spaces/#{space_id}/assets/#{asset_id}"

    contentful_request(
      asset_url,
      access_token,
      params
    )
  end

  def content_types(space_id, access_token, params \\ %{}) do
    content_types_url = "/spaces/#{space_id}/content_types"

    contentful_request(
      content_types_url,
      access_token,
      params
    )["items"]
  end

  def content_type(space_id, access_token, content_type_id, params \\ %{}) do
    content_type_url = "/spaces/#{space_id}/content_types/#{content_type_id}"

    contentful_request(
      content_type_url,
      access_token,
      params
    )
  end

  defp contentful_request(uri, access_token, params \\ %{}) do
    final_url = format_path(path: uri, params: params)

    Logger.debug "GET #{final_url}"

    get!(final_url, client_headers(access_token)).body
  end

  defp client_headers(access_token) do
    [
      {"authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"},
      {"User-Agent", "Contentful-Elixir"}
    ]
  end

  defp format_path(path: path, params: params) do
    if Enum.any?(params) do
      query = params
        |> Enum.reduce("", fn ({k, v}, acc) -> acc <> "#{k}=#{v}&" end)
        |> String.rstrip(?&)
      "#{path}/?#{query}"
    else
      path
    end
  end

  defp process_url(url) do
    "#{@protocol}://#{@endpoint}#{url}"
  end

  defp process_response_body(body) do
    body
    |> Poison.decode!
  end

  defp merge_includes(response, includes) do
    all_includes = %{
      "Asset" => includes["Asset"],
      "Entry" => Enum.concat(
        Map.get(response, "items", []),
        Map.get(includes, "Entry", [])
      )
    }

    items = if Map.has_key?(response, "items") do
      Enum.map(
        Map.get(response, "items"), fn (item) ->
          resolve_include(item, all_includes)
        end
      )
    end

    Map.merge(response, %{"items" => items})
  end

  defp resolve_includes(response) do
    if Map.has_key?(response, "items") do
      includes = Map.get(response, "includes")
      merge_includes(response, includes)
    else
      response
    end
  end

  defp resolve_include(item, includes) do
    if item["sys"]["type"] == "Entry" do
      fields = item["fields"]
      |> Enum.map(fn {name, field} ->
        {name, resolve_include_field(field, includes)}
      end)
      |> Enum.into(%{})
      |> resolve_include_field(includes)

      Map.merge(item, %{"fields" => fields})
    else
      item
    end
  end


  defp resolve_include_field(field, includes) when is_list(field) do
    Enum.map(field, fn (field) ->
      resolve_include_field(replace_field(field, includes), includes)
    end)
  end
  defp resolve_include_field(field, includes) when is_map(field) do
    Enum.map(Map.keys(field), fn (key) ->
      {key, replace_field(field[key], includes)}
    end)
    |> Enum.into(%{})
  end
  defp resolve_include_field(field, _includes), do: field

  defp replace_field(field, includes) do
    cond do
      is_map(field) && field["sys"]["type"] == "Link" && (field["sys"]["linkType"] == "Asset" || field["sys"]["linkType"] == "Entry") ->
        includes[field["sys"]["linkType"]]
        |> Enum.find(fn (match) -> match["sys"]["id"] == field["sys"]["id"] end)
        |> resolve_include_field(includes)

      true ->
        resolve_include_field(field, includes)
    end
  end
end
