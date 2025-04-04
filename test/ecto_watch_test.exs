defmodule EctoWatchTest do
  alias EctoWatch.TestRepo

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # TODO: Long module names (testing for limits of postgres labels)
  # TODO: More tests for label option
  # TODO: Pass non-lists to `extra_columns`
  # TODO: Pass strings in list to `extra_columns`

  defmodule Thing do
    use Ecto.Schema

    @moduledoc """
    A generic schema to test notifications about record changes

    Has the different types of fields that can be used in a schema
    """

    schema "things" do
      field(:the_string, :string)
      field(:the_integer, :integer)
      field(:the_float, :float, source: :theFloat)

      belongs_to(:parent_thing, Thing)
      belongs_to(:other_parent_thing, Thing, source: :otherParentThingId)

      timestamps()
    end
  end

  defmodule Other do
    use Ecto.Schema

    @moduledoc """
    This table is for testing weird edge cases like:
     * Postgres schema with characters that require quoting
     * Primary key which isn't `id`
    """

    @schema_prefix "0xabcd"

    @primary_key {:weird_id, :integer, autogenerate: false}
    schema "other" do
      field(:the_string, :string)

      timestamps()
    end
  end

  defmodule ModuleWithAReallyLongName do
    use Ecto.Schema

    @moduledoc """
    A module that *just* barely fits when creating function/trigger names
    """

    schema "a_module_with_a_really_long_name" do
      field(:the_string, :string)
    end
  end

  defmodule ModuleWithJustTooLongAName do
    use Ecto.Schema

    @moduledoc """
    A module that *just* barely fits when creating function/trigger names
    """

    schema "a_module_with_just_too_long_a_name" do
      field(:the_string, :string)
    end
  end

  setup do
    start_supervised!(TestRepo)

    start_supervised!({Phoenix.PubSub, name: TestPubSub})

    Ecto.Adapters.SQL.query!(TestRepo, "DROP SCHEMA IF EXISTS \"public\" CASCADE")
    Ecto.Adapters.SQL.query!(TestRepo, "DROP SCHEMA IF EXISTS \"0xabcd\" CASCADE")
    Ecto.Adapters.SQL.query!(TestRepo, "CREATE SCHEMA \"public\"")
    Ecto.Adapters.SQL.query!(TestRepo, "CREATE SCHEMA \"0xabcd\"")

    Ecto.Adapters.SQL.query!(
      TestRepo,
      """
        CREATE TABLE things (
          id SERIAL PRIMARY KEY,
          the_string TEXT,
          the_integer INTEGER,
          "theFloat" FLOAT,
          parent_thing_id INTEGER,
          "otherParentThingId" INTEGER,
          extra_field TEXT,
          inserted_at TIMESTAMP,
          updated_at TIMESTAMP,
          CONSTRAINT "things_parent_thing_id_fkey" FOREIGN KEY ("parent_thing_id") REFERENCES "things"("id"),
          CONSTRAINT "things_other_parent_thing_id_fkey" FOREIGN KEY ("otherParentThingId") REFERENCES "things"("id")
        )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      TestRepo,
      """
        CREATE TABLE \"0xabcd\".other (
          weird_id INTEGER,
          the_string TEXT,
          inserted_at TIMESTAMP,
          updated_at TIMESTAMP
        )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      TestRepo,
      """
        CREATE TABLE a_module_with_a_really_long_name (
          id SERIAL PRIMARY KEY,
          the_string TEXT
        )
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      TestRepo,
      """
        CREATE TABLE a_module_with_just_too_long_a_name (
          id SERIAL PRIMARY KEY,
          the_string TEXT
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
        INSERT INTO things (the_string, the_integer, \"theFloat\", extra_field, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, 'hey', NOW(), NOW())
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
        INSERT INTO things (the_string, the_integer, \"theFloat\", parent_thing_id, extra_field, inserted_at, updated_at) VALUES ('the other value', 8899, 24.52, #{already_existing_id1}, 'hey', NOW(), NOW())
        RETURNING id
        """,
        []
      )

    [
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    ]
  end

  describe "argument validation" do
    test "require valid repo" do
      assert_raise ArgumentError, ~r/required :repo option not found/, fn ->
        EctoWatch.start_link(
          pub_sub: TestPubSub,
          watchers: [
            {Thing, :inserted}
          ]
        )
      end

      assert_raise ArgumentError, ~r/invalid value for :repo option: 321 was not an atom/, fn ->
        EctoWatch.start_link(
          repo: 321,
          pub_sub: TestPubSub,
          watchers: [
            {Thing, :inserted}
          ]
        )
      end

      assert_raise ArgumentError,
                   ~r/invalid value for :repo option: NotARunningRepo was not a currently running ecto repo/,
                   fn ->
                     EctoWatch.start_link(
                       repo: NotARunningRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted}
                       ]
                     )
                   end
    end

    test "require valid pubsub" do
      assert_raise ArgumentError, ~r/required :pub_sub option not found/, fn ->
        EctoWatch.start_link(
          repo: TestRepo,
          watchers: [
            {Thing, :inserted}
          ]
        )
      end

      assert_raise ArgumentError,
                   ~r/invalid value for :pub_sub option: 123 was not an atom/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: 123,
                       watchers: [
                         {Thing, :inserted}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :pub_sub option: NotARunningPubSub was not a currently running Phoenix PubSub module/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: NotARunningPubSub,
                       watchers: [
                         {Thing, :inserted}
                       ]
                     )
                   end
    end

    test "watcher option validations" do
      assert_raise ArgumentError, ~r/required :watchers option not found/, fn ->
        EctoWatch.start_link(
          repo: TestRepo,
          pub_sub: TestPubSub
        )
      end

      assert_raise ArgumentError,
                   ~r/Invalid options: invalid value for :watchers option: should be a list/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: :not_a_list
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: Expected atom to be an Ecto schema module. Got: NotASchema/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {NotASchema, :inserted}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: update_type was not one of :inserted, :updated, or :deleted/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :bad_update_type}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: should be either `{schema_definition, update_type}` or `{schema_definition, update_type, opts}`.  Got: {EctoWatchTest.Thing}/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: should be either `{schema_definition, update_type}` or `{schema_definition, update_type, opts}`.  Got: {EctoWatchTest.Thing, :inserted, \[\], :blah}/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted, [], :blah}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: required :table_name option not found, received options: \[\]/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{}, :inserted, [label: :foo]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: Label must be used when passing in a map for schema_definition/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things}, :inserted, []}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :primary_key option: expected atom, got: 1/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things, primary_key: 1}, :inserted, [label: :foo]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :columns option: expected list, got: 1/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things, columns: 1}, :inserted, [label: :foo]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid list in :columns option: invalid value for list element at position 0: expected atom, got: 1/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things, columns: [1]}, :inserted, [label: :foo]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :association_columns option: expected list, got: 1/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things, association_columns: 1}, :inserted,
                          [label: :foo]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid list in :association_columns option: invalid value for list element at position 0: expected atom, got: 1/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {%{table_name: :things, association_columns: [1]}, :inserted,
                          [label: :foo]}
                       ]
                     )
                   end

      # Watchers which can't be disambiguated

      assert_raise ArgumentError,
                   ~r/The following labels are duplicated across watchers: thing_custom_event/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted, label: :thing_custom_event},
                         {Thing, :updated, label: :thing_custom_event}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/The following schema and update type combinations are duplicated across watchers:\n\n  \{EctoWatchTest.Thing, :inserted\}/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted, extra_columns: [:the_string]},
                         {Thing, :inserted, extra_columns: [:the_integer]}
                       ]
                     )
                   end
    end

    test "trigger_columns option only allowed for `updated`" do
      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :trigger_columns option: Cannot listen to trigger_columns for `inserted` events./,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted,
                          label: :thing_custom_event, trigger_columns: [:the_string, :the_float]}
                       ]
                     )
                   end
    end

    test "columns must be in schema" do
      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :trigger_columns option: Invalid column: :not_a_column \(expected to be in \[:id, :the_string, :the_integer, :the_float, :parent_thing_id, :other_parent_thing_id, :inserted_at, :updated_at\]\)/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :updated,
                          label: :thing_custom_event,
                          trigger_columns: [
                            :the_string,
                            :not_a_column,
                            :the_float,
                            :another_bad_column
                          ]}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :extra_columns option: Invalid column: :not_a_column \(expected to be in \[:id, :the_string, :the_integer, :the_float, :parent_thing_id, :other_parent_thing_id, :inserted_at, :updated_at\]\)/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :updated,
                          label: :thing_custom_event,
                          extra_columns: [
                            :the_string,
                            :not_a_column,
                            :the_float,
                            :another_bad_column
                          ]}
                       ]
                     )
                   end
    end

    test "label must be specified if trigger_columns is specified" do
      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :trigger_columns option: Label must be used when trigger_columns are specified/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :updated, trigger_columns: [:the_string, :the_float]}
                       ]
                     )
                   end
    end

    test "warnings about old behavior for subscribing" do
      assert_raise ArgumentError,
                   ~r/This way of subscribing was removed in version 0.8.0. Instead call:\n+subscribe\(\{EctoWatchTest.Thing, :updated\}\)/,
                   fn ->
                     EctoWatch.subscribe(Thing, :updated)
                   end

      assert_raise ArgumentError,
                   ~r/This way of subscribing was removed in version 0.8.0. Instead call:\n+subscribe\(\{EctoWatchTest.Thing, :updated\}, 123\)/,
                   fn ->
                     EctoWatch.subscribe(Thing, :updated, 123)
                   end

      assert_raise ArgumentError,
                   ~r/This way of subscribing was removed in version 0.8.0. Instead call:\n+subscribe\(:a_label\)/,
                   fn ->
                     EctoWatch.subscribe(:a_label, :updated)
                   end

      assert_raise ArgumentError,
                   ~r/This way of subscribing was removed in version 0.8.0. Instead call:\n+subscribe\(:a_label, 123\)/,
                   fn ->
                     EctoWatch.subscribe(:a_label, :updated, 123)
                   end
    end

    test "subscribe returns error if EctoWatch hasn't been started", %{
      already_existing_id1: already_existing_id1
    } do
      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe({Thing, :updated})
      end

      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe({Thing, :updated}, already_existing_id1)
      end

      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe({Thing, :updated}, {:parent_thing_id, already_existing_id1})
      end
    end

    test "Empty list of watcher is allowed" do
      start_supervised!({EctoWatch, repo: TestRepo, pub_sub: TestPubSub, watchers: []})
    end

    test "Errors should be given if the schema module is too long for creating the trigger name" do
      assert_raise RuntimeError,
                   ~r/Schema module name is 1 character\(s\) too long for the auto-generated Postgres trigger/,
                   fn ->
                     start_supervised!(
                       {EctoWatch,
                        repo: TestRepo,
                        pub_sub: TestPubSub,
                        watchers: [
                          {ModuleWithJustTooLongAName, :inserted}
                        ]}
                     )
                   end

      # Everything works fine if you're just at the limit
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {ModuleWithAReallyLongName, :inserted}
         ]}
      )

      EctoWatch.subscribe({ModuleWithAReallyLongName, :inserted})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO a_module_with_a_really_long_name (the_string) VALUES ('the value')",
        []
      )

      assert_receive {{ModuleWithAReallyLongName, :inserted}, %{id: _}}
    end

    test "Errors should be given if the label is too long" do
      assert_raise RuntimeError,
                   ~r/Label is 1 character\(s\) too long to be part of the Postgres trigger name./,
                   fn ->
                     start_supervised!(
                       {EctoWatch,
                        repo: TestRepo,
                        pub_sub: TestPubSub,
                        watchers: [
                          {ModuleWithJustTooLongAName, :inserted,
                           label: :the_label_is_also_just_much_too_long_such_a_shame}
                        ]}
                     )
                   end

      # Everything works fine if you're just at the limit
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {ModuleWithJustTooLongAName, :inserted,
            label: :the_label_is_also_just_much_too_long_such_a_sham}
         ]}
      )

      EctoWatch.subscribe(:the_label_is_also_just_much_too_long_such_a_sham)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO a_module_with_just_too_long_a_name (the_string) VALUES ('the value')",
        []
      )

      assert_receive {:the_label_is_also_just_much_too_long_such_a_sham, %{id: _}}
    end

    test "subscribe requires proper Ecto schema", %{
      already_existing_id1: already_existing_id1
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Expected atom to be an Ecto schema module. Got: NotASchema/,
                   fn ->
                     EctoWatch.subscribe({NotASchema, :updated})
                   end

      assert_raise ArgumentError,
                   ~r/Expected atom to be an Ecto schema module. Got: NotASchema/,
                   fn ->
                     EctoWatch.subscribe({NotASchema, :updated}, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   ~r/Expected atom to be an Ecto schema module. Got: NotASchema/,
                   fn ->
                     EctoWatch.subscribe(
                       {NotASchema, :updated},
                       {:parent_thing_id, already_existing_id1}
                     )
                   end
    end

    test "requires one of three arguments", %{
      already_existing_id1: already_existing_id1
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated}
         ]}
      )

      assert_raise ArgumentError,
                   "Unexpected update_type: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe({Thing, :something_else})
                   end

      assert_raise ArgumentError,
                   "Invalid subscription (expected either `{schema_module, :inserted | :updated | :deleted}` or a label): {EctoWatchTest.Thing, 1234}",
                   fn ->
                     EctoWatch.subscribe({Thing, 1234})
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe({Thing, :something_else}, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   "Invalid subscription (expected either `{schema_module, :inserted | :updated | :deleted}` or a label): {EctoWatchTest.Thing, 1234}",
                   fn ->
                     EctoWatch.subscribe({Thing, 1234}, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(
                       {Thing, :something_else},
                       {:parent_thing_id, already_existing_id1}
                     )
                   end

      assert_raise ArgumentError,
                   "Invalid subscription (expected either `{schema_module, :inserted | :updated | :deleted}` or a label): {EctoWatchTest.Thing, 1234}",
                   fn ->
                     EctoWatch.subscribe({Thing, 1234}, {:parent_thing_id, already_existing_id1})
                   end
    end
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
          AFTER UPDATE ON \"public\".\"things\" FOR EACH ROW
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
          AFTER UPDATE ON \"public\".\"things\" FOR EACH ROW
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
               {Thing, :inserted, label: :trigger_test}
             ]}
          )

          Process.sleep(2_000)
        end)

      assert log =~
               ~r/Found the following extra EctoWatch triggers:\n\n"ew_some_weird_trigger" in the table "public"\."things"\n\n\.\.\.but they were not specified in the watcher options/

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
           {Thing, :inserted, label: :trigger_test}
         ]}
      )

      Process.sleep(2_000)

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
    test "Error when trying to subscribe to insert of an ID" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Cannot subscribe to primary_key for inserted records because primary key values aren't created until the insert happens/,
                   fn ->
                     EctoWatch.subscribe({Thing, :inserted}, 123)
                   end
    end

    test "get notification about inserts" do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :inserted},
         {Other, :inserted},
         # schemaless definition
         {%{table_name: :things}, :inserted, label: :things_inserted},
         {%{table_name: :other, schema_prefix: "0xabcd", primary_key: :weird_id}, :inserted,
          label: :other_inserted}
       ]})

      EctoWatch.subscribe({Thing, :inserted})
      EctoWatch.subscribe({Other, :inserted})
      EctoWatch.subscribe(:things_inserted)
      EctoWatch.subscribe(:other_inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (1234, 'the value', NOW(), NOW())",
        []
      )

      assert_receive {{Thing, :inserted}, %{id: 3}}
      assert_receive {:things_inserted, %{id: 3}}
      assert_receive {{Other, :inserted}, %{weird_id: 1234}}
      assert_receive {:other_inserted, %{weird_id: 1234}}

      EctoWatch.unsubscribe({Thing, :inserted})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      refute_receive {{Thing, :inserted}, _}
      assert_receive {:things_inserted, %{id: 4}}

      EctoWatch.unsubscribe(:things_inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      refute_receive {{Thing, :inserted}, _}
      refute_receive {:things_inserted, _}

      EctoWatch.unsubscribe({Other, :inserted})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (2345, 'the value', NOW(), NOW())",
        []
      )

      refute_receive {{Other, :inserted}, %{weird_id: 2345}}
      assert_receive {:other_inserted, %{weird_id: 2345}}

      EctoWatch.unsubscribe(:other_inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (3456, 'the value', NOW(), NOW())",
        []
      )

      refute_receive {:other_inserted, _}
    end

    test "empty extra_columns list" do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :inserted, extra_columns: []},
         {Other, :inserted, extra_columns: []},
         # schemaless definition
         {%{table_name: :things}, :inserted, label: :things_inserted, extra_columns: []},
         {%{table_name: :other, schema_prefix: "0xabcd", primary_key: :weird_id}, :inserted,
          label: :other_inserted, extra_columns: []}
       ]})

      EctoWatch.subscribe({Thing, :inserted})
      EctoWatch.subscribe({Other, :inserted})
      EctoWatch.subscribe(:things_inserted)
      EctoWatch.subscribe(:other_inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (1234, 'the value', NOW(), NOW())",
        []
      )

      assert_receive {{Thing, :inserted}, %{id: 3}}
      assert_receive {:things_inserted, %{id: 3}}
      assert_receive {{Other, :inserted}, %{weird_id: 1234}}
      assert_receive {:other_inserted, %{weird_id: 1234}}

      EctoWatch.unsubscribe({Thing, :inserted})
      EctoWatch.unsubscribe({Other, :inserted})
      EctoWatch.unsubscribe(:things_inserted)
      EctoWatch.unsubscribe(:other_inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (2345, 'the value', NOW(), NOW())",
        []
      )

      refute_receive {{Thing, :inserted}, _}
      refute_receive {:things_inserted, _}
      refute_receive {{Other, :inserted}, _}
      refute_receive {:other_inserted, _}
    end

    test "inserts for an association column", %{already_existing_id2: already_existing_id2} do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted, extra_columns: [:parent_thing_id]},
           {%{
              table_name: :things,
              columns: [:parent_thing_id],
              association_columns: [:parent_thing_id]
            }, :inserted, extra_columns: [:parent_thing_id], label: :things_parent_id_inserted}
         ]}
      )

      EctoWatch.subscribe({Thing, :inserted}, {:parent_thing_id, already_existing_id2})

      EctoWatch.subscribe(
        :things_parent_id_inserted,
        {:parent_thing_id, already_existing_id2}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", parent_thing_id, extra_field, inserted_at, updated_at) VALUES ('the other value', 8900, 24.53, #{already_existing_id2}, 'hey', NOW(), NOW())",
        []
      )

      assert_receive {{Thing, :inserted}, %{id: 3, parent_thing_id: ^already_existing_id2}}

      assert_receive {:things_parent_id_inserted,
                      %{id: 3, parent_thing_id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :inserted}, {:parent_thing_id, already_existing_id2})

      EctoWatch.unsubscribe(
        :things_parent_id_inserted,
        {:parent_thing_id, already_existing_id2}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", parent_thing_id, extra_field, inserted_at, updated_at) VALUES ('the other value', 8900, 24.53, #{already_existing_id2}, 'hey', NOW(), NOW())",
        []
      )

      refute_receive {{Thing, :inserted}, _}

      refute_receive {:things_parent_id_inserted, _}
    end

    test "column is not in list of extra_columns", %{already_existing_id2: already_existing_id2} do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted, extra_columns: [:parent_thing_id]}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column other_parent_thing_id is not in the list of extra columns/,
                   fn ->
                     EctoWatch.subscribe(
                       {Thing, :inserted},
                       {:other_parent_thing_id, already_existing_id2}
                     )
                   end
    end

    test "column is not association column" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted, extra_columns: [:the_string]}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column the_string is not an association column/,
                   fn ->
                     EctoWatch.subscribe({Thing, :inserted}, {:the_string, "test"})
                   end
    end

    test "no notification without subscribe" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted},
           {Other, :inserted}
         ]}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (4321, 'the value', NOW(), NOW())",
        []
      )

      refute_receive {{Thing, :inserted}, %{}}
      refute_receive {{Other, :inserted}, %{}}
    end
  end

  describe "updated" do
    test "all updates", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :updated},
         # schemaless definition
         {%{table_name: :things}, :updated, label: :things_updated}
       ]})

      EctoWatch.subscribe({Thing, :updated})
      EctoWatch.subscribe(:things_updated)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {{Thing, :updated}, %{id: ^already_existing_id1}}
      assert_receive {:things_updated, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :updated}, %{id: ^already_existing_id2}}
      assert_receive {:things_updated, %{id: ^already_existing_id2}}
    end

    test "empty column lists", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :updated, trigger_columns: [], extra_columns: []},
         # schemaless definition
         {%{table_name: :things}, :updated,
          label: :things_updated, trigger_columns: [], extra_columns: []}
       ]})

      EctoWatch.subscribe({Thing, :updated})
      EctoWatch.subscribe(:things_updated)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {{Thing, :updated}, %{id: ^already_existing_id1}}
      assert_receive {:things_updated, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :updated}, %{id: ^already_existing_id2}}
      assert_receive {:things_updated, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :updated})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'the second new value'",
        []
      )

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id1}}
      assert_receive {:things_updated, %{id: ^already_existing_id1}}

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id2}}
      assert_receive {:things_updated, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe(:things_updated)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'the third new value'",
        []
      )

      refute_receive {:things_updated, %{id: ^already_existing_id1}}
      refute_receive {:things_updated, %{id: ^already_existing_id2}}
    end

    test "updates for the primary key", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated}
         ]}
      )

      EctoWatch.subscribe({Thing, :updated}, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {{Thing, :updated}, %{id: ^already_existing_id1}}

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :updated}, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'another new value'", [])

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id1}}
    end

    test "updates for an association column", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated, extra_columns: [:parent_thing_id]},
           {%{
              table_name: :things,
              columns: [:parent_thing_id],
              association_columns: [:parent_thing_id]
            }, :updated, extra_columns: [:parent_thing_id], label: :things_parent_id_updated}
         ]}
      )

      EctoWatch.subscribe({Thing, :updated}, {:parent_thing_id, already_existing_id1})

      EctoWatch.subscribe(
        :things_parent_id_updated,
        {:parent_thing_id, already_existing_id1}
      )

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id1}}
      refute_receive {:things_parent_id_updated, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :updated},
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}

      assert_receive {:things_parent_id_updated,
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}

      EctoWatch.unsubscribe({Thing, :updated}, {:parent_thing_id, already_existing_id1})

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'another new value'", [])

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id2}}

      assert_receive {:things_parent_id_updated,
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}

      EctoWatch.unsubscribe(
        :things_parent_id_updated,
        {:parent_thing_id, already_existing_id1}
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'yet another new value'",
        []
      )

      refute_receive {:things_parent_id_updated, %{id: ^already_existing_id2}}
    end

    test "column is not in list of extra_columns", %{already_existing_id2: already_existing_id2} do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated, extra_columns: [:parent_thing_id]}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column other_parent_thing_id is not in the list of extra columns/,
                   fn ->
                     EctoWatch.subscribe(
                       {Thing, :updated},
                       {:other_parent_thing_id, already_existing_id2}
                     )
                   end
    end

    test "column is not association column" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column the_string is not an association column/,
                   fn ->
                     EctoWatch.subscribe({Thing, :updated}, {:the_string, "test"})
                   end
    end

    test "trigger_columns option", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated,
            label: :thing_custom_event, trigger_columns: [:the_integer, :the_float]}
         ]}
      )

      EctoWatch.subscribe(:thing_custom_event, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {_, %{id: ^already_existing_id1}}
      refute_receive {_, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9999", [])

      assert_receive {:thing_custom_event, %{id: ^already_existing_id1}}
      refute_receive {_, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET \"theFloat\" = 99.999", [])

      assert_receive {:thing_custom_event, %{id: ^already_existing_id1}}
      refute_receive {_, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe(:thing_custom_event, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])
      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9998", [])
      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET \"theFloat\" = 99.899", [])

      refute_receive {_, %{id: ^already_existing_id1}}
      refute_receive {_, %{id: ^already_existing_id2}}
    end

    test "extra_columns option", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated, extra_columns: [:the_integer, :the_float]}
         ]}
      )

      EctoWatch.subscribe({Thing, :updated}, already_existing_id1)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'the new value' WHERE id = $1",
        [already_existing_id1]
      )

      assert_receive {{Thing, :updated},
                      %{id: ^already_existing_id1, the_integer: 4455, the_float: 84.52}}

      refute_receive {{_, :updated}, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9999 WHERE id = $1", [
        already_existing_id1
      ])

      assert_receive {{Thing, :updated},
                      %{id: ^already_existing_id1, the_integer: 9999, the_float: 84.52}}

      refute_receive {{_, :updated}, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET \"theFloat\" = 99.999 WHERE id = $1",
        [
          already_existing_id1
        ]
      )

      assert_receive {{Thing, :updated},
                      %{id: ^already_existing_id1, the_integer: 9999, the_float: 99.999}}

      refute_receive {{_, :updated}, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :updated}, already_existing_id1)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'another new value' WHERE id = $1",
        [already_existing_id1]
      )

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9999 WHERE id = $1", [
        already_existing_id1
      ])

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET \"theFloat\" = 99.999 WHERE id = $1",
        [
          already_existing_id1
        ]
      )

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id1}}

      refute_receive {{_, :updated}, %{id: ^already_existing_id2}}
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id1}}

      refute_receive {{Thing, :updated}, %{id: ^already_existing_id2}}
    end
  end

  describe "deleted" do
    test "all deletes", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :deleted},
         # schemaless definition
         {%{table_name: :things}, :deleted, label: :things_deleted}
       ]})

      EctoWatch.subscribe({Thing, :deleted})
      EctoWatch.subscribe(:things_deleted)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {{Thing, :deleted}, %{id: ^already_existing_id1}}
      assert_receive {:things_deleted, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :deleted}, %{id: ^already_existing_id2}}
      assert_receive {:things_deleted, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :deleted})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, _}

      assert_receive {:things_deleted, %{id: 3}}

      EctoWatch.unsubscribe(:things_deleted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, _}
      refute_receive {:things_deleted, _}
    end

    test "empty extra_columns", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!({EctoWatch,
       repo: TestRepo,
       pub_sub: TestPubSub,
       watchers: [
         {Thing, :deleted, extra_columns: []},
         # schemaless definition
         {%{table_name: :things}, :deleted, label: :things_deleted, extra_columns: []}
       ]})

      EctoWatch.subscribe({Thing, :deleted})
      EctoWatch.subscribe(:things_deleted)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {{Thing, :deleted}, %{id: ^already_existing_id1}}
      assert_receive {:things_deleted, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :deleted}, %{id: ^already_existing_id2}}
      assert_receive {:things_deleted, %{id: ^already_existing_id2}}

      EctoWatch.unsubscribe({Thing, :deleted})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, _}
      assert_receive {:things_deleted, %{id: 3}}

      EctoWatch.unsubscribe(:things_deleted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, _}
      refute_receive {:things_deleted, _}
    end

    test "deletes for the primary key", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :deleted}
         ]}
      )

      EctoWatch.subscribe({Thing, :deleted}, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {{Thing, :deleted}, %{id: ^already_existing_id1}}

      refute_receive {{Thing, :deleted}, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, \"theFloat\", inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      EctoWatch.subscribe({Thing, :deleted}, 3)
      EctoWatch.unsubscribe({Thing, :deleted}, 3)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, _}
    end

    test "deletes for an association column", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :deleted, extra_columns: [:parent_thing_id]},
           {%{
              table_name: :things,
              columns: [:parent_thing_id],
              association_columns: [:parent_thing_id]
            }, :deleted, extra_columns: [:parent_thing_id], label: :things_parent_id_deleted}
         ]}
      )

      EctoWatch.subscribe({Thing, :deleted}, {:parent_thing_id, already_existing_id1})

      EctoWatch.subscribe(
        :things_parent_id_deleted,
        {:parent_thing_id, already_existing_id1}
      )

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, %{id: ^already_existing_id1}}
      refute_receive {:things_parent_id_deleted, %{id: ^already_existing_id1}}

      assert_receive {{Thing, :deleted},
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}

      assert_receive {:things_parent_id_deleted,
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}
    end

    test "column is not in list of extra_columns", %{
      already_existing_id2: already_existing_id2
    } do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :deleted, extra_columns: [:parent_thing_id]}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column other_parent_thing_id is not in the list of extra columns/,
                   fn ->
                     EctoWatch.subscribe(
                       {Thing, :deleted},
                       {:other_parent_thing_id, already_existing_id2}
                     )
                   end
    end

    test "column is not association column" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :deleted}
         ]}
      )

      assert_raise ArgumentError,
                   ~r/Column the_string is not an association column/,
                   fn ->
                     EctoWatch.subscribe({Thing, :deleted}, {:the_string, "test"})
                   end
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {{Thing, :deleted}, %{id: ^already_existing_id1}}

      refute_receive {{Thing, :deleted}, %{id: ^already_existing_id2}}
    end
  end

  describe "details" do
    test "for standard and labeled" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :updated, label: :thing_custom_event},
           {Thing, :deleted}
         ]}
      )

      details = EctoWatch.details({Thing, :deleted})

      assert details.repo_mod == TestRepo

      assert details.schema_definition == %EctoWatch.Options.WatcherOptions.SchemaDefinition{
               schema_prefix: "public",
               table_name: "things",
               primary_key: :id,
               column_map: %{
                 id: :id,
                 inserted_at: :inserted_at,
                 other_parent_thing_id: :otherParentThingId,
                 parent_thing_id: :parent_thing_id,
                 the_float: :theFloat,
                 the_integer: :the_integer,
                 the_string: :the_string,
                 updated_at: :updated_at
               },
               columns: [
                 :id,
                 :the_string,
                 :the_integer,
                 :the_float,
                 :parent_thing_id,
                 :other_parent_thing_id,
                 :inserted_at,
                 :updated_at
               ],
               association_columns: [:parent_thing_id, :other_parent_thing_id],
               label: EctoWatchTest.Thing
             }

      assert details.function_name == "ew_deleted_for_ectowatchtest_thing_func"
      assert details.trigger_name == "ew_deleted_for_ectowatchtest_thing_trigger"
      assert details.notify_channel == "ew_deleted_for_ectowatchtest_thing"

      details = EctoWatch.details(:thing_custom_event)

      assert details.repo_mod == TestRepo

      assert details.schema_definition == %EctoWatch.Options.WatcherOptions.SchemaDefinition{
               schema_prefix: "public",
               table_name: "things",
               primary_key: :id,
               column_map: %{
                 id: :id,
                 inserted_at: :inserted_at,
                 other_parent_thing_id: :otherParentThingId,
                 parent_thing_id: :parent_thing_id,
                 the_float: :theFloat,
                 the_integer: :the_integer,
                 the_string: :the_string,
                 updated_at: :updated_at
               },
               columns: [
                 :id,
                 :the_string,
                 :the_integer,
                 :the_float,
                 :parent_thing_id,
                 :other_parent_thing_id,
                 :inserted_at,
                 :updated_at
               ],
               association_columns: [:parent_thing_id, :other_parent_thing_id],
               label: EctoWatchTest.Thing
             }

      assert details.function_name == "ew_for_thing_custom_event_func"
      assert details.trigger_name == "ew_for_thing_custom_event_trigger"
      assert details.notify_channel == "ew_for_thing_custom_event"
    end
  end

  describe "debug? option" do
    test "option on specific watcher" do
      log =
        capture_log([level: :debug], fn ->
          start_supervised!(
            {EctoWatch,
             repo: TestRepo,
             pub_sub: TestPubSub,
             watchers: [
               {Thing, :updated,
                extra_columns: [:the_string], label: :custom_event1, debug?: true},
               {Thing, :updated, extra_columns: [:the_integer], label: :custom_event2}
             ]}
          )
        end)

      assert log =~ ~r/EctoWatch \| :custom_event1 \| #PID<\d+\.\d+\.\d+> \| Starting server/
      refute log =~ ~r/EctoWatch \| custom_event2/

      log =
        capture_log([level: :debug], fn ->
          Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

          Process.sleep(1_000)
        end)

      assert log =~
               ~r/Received Postgrex notification on channel `ew_for_custom_event1`: {"type": "updated", "values": {"id": 1, "the_string": "the new value"}}/

      refute log =~ ~r/Received Postgrex notification on channel `ew_for_custom_event2`/

      assert log =~
               ~r/Broadcasting to Phoenix PubSub topic `ew_for_custom_event1`: {:custom_event1, %{id: 1, the_string: "the new value"}}/

      refute log =~ ~r/Broadcasting to Phoenix PubSub topic `ew_for_custom_event2`/

      log =
        capture_log([level: :info], fn ->
          Ecto.Adapters.SQL.query!(
            TestRepo,
            "UPDATE things SET the_string = 'the new new value'",
            []
          )

          Process.sleep(1_000)
        end)

      refute log =~ ~r/Received Postgrex notification on channel/
      refute log =~ ~r/Broadcasting to Phoenix PubSub topic/

      log =
        capture_log([level: :debug], fn ->
          EctoWatch.subscribe(:custom_event1)
        end)

      assert log =~
               ~r/EctoWatch \| :custom_event1 \| #PID<\d+\.\d+\.\d+> \| Subscribing to watcher/

      refute log =~ ~r/EctoWatch \| :custom_event2/

      log =
        capture_log([level: :debug], fn ->
          EctoWatch.subscribe(:custom_event2)
        end)

      refute log =~ ~r/EctoWatch \| :custom_event1/
      refute log =~ ~r/EctoWatch \| :custom_event2/

      log =
        capture_log([level: :info], fn ->
          EctoWatch.subscribe(:custom_event1)
          EctoWatch.subscribe(:custom_event2)
        end)

      refute log =~ ~r/EctoWatch \| :custom_event/
    end

    test "global option" do
      log =
        capture_log([level: :debug], fn ->
          start_supervised!(
            {EctoWatch,
             repo: TestRepo,
             pub_sub: TestPubSub,
             debug?: true,
             watchers: [
               {Thing, :updated, extra_columns: [:the_string], label: :custom_event1},
               {Thing, :updated, extra_columns: [:the_integer], label: :custom_event2}
             ]}
          )
        end)

      assert log =~ ~r/EctoWatch \| :custom_event1 \| #PID<\d+\.\d+\.\d+> \| Starting server/
      assert log =~ ~r/EctoWatch \| :custom_event2 \| #PID<\d+\.\d+\.\d+> \| Starting server/

      log =
        capture_log([level: :debug], fn ->
          Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

          Process.sleep(1_000)
        end)

      assert log =~
               ~r/Received Postgrex notification on channel `ew_for_custom_event1`: {"type": "updated", "values": {"id": 1, "the_string": "the new value"}}/

      assert log =~
               ~r/Received Postgrex notification on channel `ew_for_custom_event2`: {"type": "updated", "values": {"id": 1, "the_integer": 4455}}/

      assert log =~
               ~r/Broadcasting to Phoenix PubSub topic `ew_for_custom_event1`: {:custom_event1, %{id: 1, the_string: "the new value"}}/

      assert log =~
               ~r/Broadcasting to Phoenix PubSub topic `ew_for_custom_event2`: {:custom_event2, %{id: 1, the_integer: 4455}}/

      log =
        capture_log([level: :info], fn ->
          Ecto.Adapters.SQL.query!(
            TestRepo,
            "UPDATE things SET the_string = 'the new new value'",
            []
          )

          Process.sleep(1_000)
        end)

      refute log =~ ~r/Received Postgrex notification on channel/
      refute log =~ ~r/Broadcasting to Phoenix PubSub topic/

      log =
        capture_log([level: :debug], fn ->
          EctoWatch.subscribe(:custom_event1)
        end)

      assert log =~
               ~r/EctoWatch \| :custom_event1 \| #PID<\d+\.\d+\.\d+> \| Subscribing to watcher/

      refute log =~ ~r/EctoWatch \| :custom_event2/

      log =
        capture_log([level: :debug], fn ->
          EctoWatch.subscribe(:custom_event2)
        end)

      refute log =~ ~r/EctoWatch \| :custom_event1/

      assert log =~
               ~r/EctoWatch \| :custom_event2 \| #PID<\d+\.\d+\.\d+> \| Subscribing to watcher/

      log =
        capture_log([level: :info], fn ->
          EctoWatch.subscribe(:custom_event1)
          EctoWatch.subscribe(:custom_event2)
        end)

      refute log =~ ~r/EctoWatch \| :custom_event/
    end
  end
end
