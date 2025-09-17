defmodule EctoWatch.DB do
  @moduledoc "Mockable simple queries to PostgreSQL"

  @callback max_identifier_length(repo_mod :: atom()) :: integer()
  @callback major_version(repo_mod :: atom()) :: integer()

  def supports_create_or_replace_trigger?(repo_mod) do
    major_version(repo_mod) >= 14
  end

  def max_identifier_length(repo_mod), do: mod().max_identifier_length(repo_mod)
  def major_version(repo_mod), do: mod().major_version(repo_mod)

  defp mod do
    Application.get_env(:ecto_watch, EctoWatch.DB)[:mod] || EctoWatch.DB.Live
  end
end

defmodule EctoWatch.DB.Live do
  @moduledoc "Actual implementation of EctoWatch.DB"

  @behaviour EctoWatch.DB

  def max_identifier_length(repo_mod) do
    query_for_value(repo_mod, "SHOW max_identifier_length")
    |> String.to_integer()
  end

  def major_version(repo_mod) do
    version_string = query_for_value(repo_mod, "SHOW server_version")

    case Integer.parse(version_string) do
      {major_version, _} ->
        major_version

      _ ->
        raise "Unable to parse PostgreSQL major version number from version string: #{inspect(version_string)}"
    end
  end

  defp query_for_value(repo_mod, query) do
    case Ecto.Adapters.SQL.query!(repo_mod, query, []) do
      %Postgrex.Result{rows: [[value]]} ->
        value

      other ->
        raise "Unexpected result when making query `#{query}`: #{inspect(other)}"
    end
  end
end
