defmodule EctoWatch.TestRepo do
  @moduledoc "Repo for tests"

  use Ecto.Repo,
    otp_app: :ecto_watch,
    adapter: Ecto.Adapters.Postgres

  def init(_type, config) do
    {:ok,
     Keyword.merge(
       config,
       username: "postgres",
       password: "postgres",
       hostname: "localhost",
       database: "ecto_watch",
       stacktrace: true,
       show_sensitive_data_on_connection_error: true,
       pool_size: 10
     )}
  end
end
