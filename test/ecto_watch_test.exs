defmodule EctoWatchTest do
  use ExUnit.Case, async: true

  defmodule Thing do
    use Ecto.Schema

    @moduledoc """
    A generic schema to test notifications about record changes

    Has the different types of fields that can be used in a schema
    """

    schema "things" do
      field(:the_string, :string)
      field(:the_integer, :integer)
      field(:the_float, :float)

      timestamps()
    end
  end

  defmodule TestRepo do
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

  setup do
    start_supervised!(TestRepo)

    start_supervised!({Phoenix.PubSub, name: TestPubSub})

    Ecto.Adapters.SQL.query!(TestRepo, "DROP TABLE IF EXISTS things", [])
    Ecto.Adapters.SQL.query!(TestRepo, "CREATE TABLE things (
      id SERIAL PRIMARY KEY,
      the_string TEXT,
      the_integer INTEGER,
      the_float FLOAT,
      extra_field TEXT,
      inserted_at TIMESTAMP,
      updated_at TIMESTAMP
    )", [])

    %Postgrex.Result{
      rows: [[already_existing_id1]]
    } =
      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        INSERT INTO things (the_string, the_integer, the_float, extra_field, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, 'hey', NOW(), NOW())
        RETURNING id
        """,
        []
      )

    %Postgrex.Result{
      rows: [[already_existing_id2]]
    } =
      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        INSERT INTO things (the_string, the_integer, the_float, extra_field, inserted_at, updated_at) VALUES ('the other value', 8899, 24.52, 'hey', NOW(), NOW())
        RETURNING id
        """,
        []
      )

    start_supervised!({EctoWatch, {TestRepo, TestPubSub, [Thing]}})

    [
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    ]
  end

  describe "argument validation" do
    test "requires one of three arguments" do
      assert_raise ArgumentError,
                   "Unexpected subscription event: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, :something_else)
                   end

      assert_raise ArgumentError,
                   "Unexpected subscription event: 1234.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, 1234)
                   end
    end
  end

  describe "inserts" do
    test "get notification about inserts" do
      EctoWatch.subscribe(Thing, :inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        INSERT INTO things (the_string, the_integer, the_float, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())
        """,
        []
      )

      assert_receive {:inserted, Thing, _}
    end

    test "no notification without subscribe" do
      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        INSERT INTO things (the_string, the_integer, the_float, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())
        """,
        []
      )

      refute_receive {:inserted, %Thing{}}
    end
  end

  describe "updated" do
    test "all updates", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      EctoWatch.subscribe(Thing, :updated)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {:updated, Thing, already_existing_id1}

      assert_receive {:updated, Thing, already_existing_id2}
    end

    test "updates for an id", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      EctoWatch.subscribe(Thing, :updated, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {:updated, Thing, already_existing_id1}

      refute_receive {:updated, Thing, already_existing_id2}
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {:updated, Thing, already_existing_id1}

      refute_receive {:updated, Thing, already_existing_id2}
    end
  end

  describe "deleted" do
    test "all deletes", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      EctoWatch.subscribe(Thing, :deleted)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {:deleted, Thing, already_existing_id1}

      assert_receive {:deleted, Thing, already_existing_id2}
    end

    test "deletes for an id", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      EctoWatch.subscribe(Thing, :deleted, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {:deleted, Thing, already_existing_id1}

      refute_receive {:deleted, Thing, already_existing_id2}
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {:deleted, Thing, already_existing_id1}

      refute_receive {:deleted, Thing, already_existing_id2}
    end
  end
end
