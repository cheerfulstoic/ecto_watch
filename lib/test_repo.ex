defmodule EctoWatch.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :ecto_watch,
    adapter: Ecto.Adapters.Postgres

  def init(_type, config) do
    {:ok,
     Keyword.merge(
       config,
       username: System.get_env("PGUSER", "postgres"),
       password: System.get_env("PGPASSWORD", "postgres"),
       hostname: System.get_env("PGHOST", "localhost"),
       database: System.get_env("PGDATABASE", "ecto_watch"),
       port: System.get_env("PGPORT", "5432"),
       stacktrace: true,
       show_sensitive_data_on_connection_error: true,
       pool_size: 10
     )}
  end
end
