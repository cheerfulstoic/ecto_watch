defmodule EctoWatchTest do
  alias EctoWatch.TestRepo
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  defmodule SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong do
    use Ecto.Schema

    schema "super_long" do
      field(:the_string, :string)
      timestamps()
    end
  end

  setup do
    start_supervised!(TestRepo)
    start_supervised!({Phoenix.PubSub, name: TestPubSub})
    Ecto.Adapters.SQL.query!(TestRepo, "DROP SCHEMA IF EXISTS \"public\" CASCADE")
    Ecto.Adapters.SQL.query!(TestRepo, "CREATE SCHEMA \"public\"")

    Ecto.Adapters.SQL.query!(
      TestRepo,
      """
        CREATE TABLE super_long (
          id SERIAL PRIMARY KEY,
          the_string TEXT,
          inserted_at TIMESTAMP,
          updated_at TIMESTAMP
        )
      """,
      []
    )

    %Postgrex.Result{
      rows: [[already_existing_id1]]
    } =
      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        INSERT INTO super_long (the_string, inserted_at, updated_at) VALUES ('super_long', NOW(), NOW())
        RETURNING id
        """,
        []
      )

    [
      already_existing_id1: already_existing_id1
    ]
  end

  describe "trigger cleanup" do
    setup do
      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        CREATE OR REPLACE FUNCTION \"public\".ew_some_weird_func()
          RETURNS trigger AS $trigger$
          BEGIN
            RETURN NEW;
          END;
          $trigger$ LANGUAGE plpgsql;
        """,
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        CREATE TRIGGER ew_some_weird_trigger
          AFTER UPDATE ON \"public\".\"super_long\" FOR EACH ROW
          EXECUTE PROCEDURE \"public\".ew_some_weird_func();
        """,
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        CREATE OR REPLACE FUNCTION \"public\".non_ecto_watch_func()
          RETURNS trigger AS $trigger$
          BEGIN
            RETURN NEW;
          END;
          $trigger$ LANGUAGE plpgsql;
        """,
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        """
        CREATE TRIGGER non_ecto_watch_trigger
          AFTER UPDATE ON \"public\".\"super_long\" FOR EACH ROW
          EXECUTE PROCEDURE \"public\".non_ecto_watch_func();
        """,
        []
      )

      :ok
    end

    test "warns about extra triggers" do
      log =
        capture_log(fn ->
          start_supervised!(
            {EctoWatch,
             repo: TestRepo,
             pub_sub: TestPubSub,
             watchers: [
               {SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong,
                :inserted, label: :trigger_test}
             ]}
          )

          Process.sleep(2_000)
        end)

      IO.inspect(log, label: :log)

      assert log =~
               ~r/Found the following extra EctoWatch triggers:\n\n"ew_some_weird_trigger" in the table "public"\."super_long"\n\n\.\.\.but they were not specified in the watcher options/

      assert log =~
               ~r/Found the following extra EctoWatch functions:\n\n"ew_some_weird_func" in the schema "public"/

      refute log =~ ~r/non_ecto_watch_trigger/
      refute log =~ ~r/non_ecto_watch_func/
    end

    test "actual cleanup" do
      System.put_env("ECTO_WATCH_CLEANUP", "cleanup")

      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong, :inserted,
            label: :trigger_test}
         ]}
      )

      Process.sleep(1_000)

      System.delete_env("ECTO_WATCH_CLEANUP")

      %Postgrex.Result{rows: rows} =
        Ecto.Adapters.SQL.query!(
          TestRepo,
          """
          SELECT trigger_name
          FROM information_schema.triggers
          """,
          []
        )

      values = Enum.map(rows, &List.first/1)

      assert "ew_some_weird_trigger" not in values
      assert "non_ecto_watch_trigger" in values

      %Postgrex.Result{rows: rows} =
        Ecto.Adapters.SQL.query!(
          TestRepo,
          """
          SELECT p.proname AS name
          FROM pg_proc p LEFT JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          """,
          []
        )

      values = Enum.map(rows, &List.first/1)

      assert "ew_some_weird_func" not in values
      assert "non_ecto_watch_func" in values
    end
  end

  describe "inserts" do
    test "get notification about inserts" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong, :inserted}
         ]}
      )

      EctoWatch.subscribe(
        {SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong, :inserted}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO super_long (the_string, inserted_at, updated_at) VALUES ('new value', NOW(), NOW())",
        []
      )

      assert_receive {{SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong,
                       :inserted}, %{id: 2}}

      EctoWatch.unsubscribe(
        {SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong, :inserted}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO super_long (the_string, inserted_at, updated_at) VALUES ('the value',  NOW(), NOW())",
        []
      )

      refute_receive {{SuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLongSuperLong,
                       :inserted}, _}
    end
  end
end
