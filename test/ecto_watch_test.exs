defmodule EctoWatchTest do
  alias EctoWatch.TestRepo

  use ExUnit.Case, async: false

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
      field(:the_float, :float)

      belongs_to(:parent_thing, Thing)
      belongs_to(:other_parent_thing, Thing)

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
          the_float FLOAT,
          parent_thing_id INTEGER,
          extra_field TEXT,
          inserted_at TIMESTAMP,
          updated_at TIMESTAMP,
          CONSTRAINT "things_parent_thing_id_fkey" FOREIGN KEY ("parent_thing_id") REFERENCES "things"("id")
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
        INSERT INTO things (the_string, the_integer, the_float, parent_thing_id, extra_field, inserted_at, updated_at) VALUES ('the other value', 8899, 24.52, #{already_existing_id1}, 'hey', NOW(), NOW())
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

    test "require at least one watcher" do
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
                   ~r/invalid value for :watchers option: requires at least one watcher/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: []
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :schema_mod option: Expected schema_mod to be an Ecto schema module. Got: NotASchema/,
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
                   ~r/invalid value for :watchers option: invalid value for :update_type option: expected one of \[:inserted, :updated, :deleted\], got: :bad_update_type/,
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
                   ~r/invalid value for :watchers option: should be either `{schema_mod, update_type}` or `{schema_mod, update_type, opts}`.  Got: {EctoWatchTest.Thing}/,
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
                   ~r/invalid value for :watchers option: should be either `{schema_mod, update_type}` or `{schema_mod, update_type, opts}`.  Got: {EctoWatchTest.Thing, :inserted, \[\], :blah}/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :inserted, [], :blah}
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

    test "columns must be non-empty" do
      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :trigger_columns option: List must not be empty/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :updated, label: :thing_custom_event, trigger_columns: []}
                       ]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :extra_columns option: List must not be empty/,
                   fn ->
                     EctoWatch.start_link(
                       repo: TestRepo,
                       pub_sub: TestPubSub,
                       watchers: [
                         {Thing, :updated, label: :thing_custom_event, extra_columns: []}
                       ]
                     )
                   end
    end

    test "columns must be in schema" do
      assert_raise ArgumentError,
                   ~r/invalid value for :watchers option: invalid value for :trigger_columns option: Invalid columns for EctoWatchTest.Thing: \[:not_a_column, :another_bad_column\]/,
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
                   ~r/invalid value for :watchers option: invalid value for :extra_columns option: Invalid columns for EctoWatchTest.Thing: \[:not_a_column, :another_bad_column\]/,
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

    test "subscribe returns error if EctoWatch hasn't been started", %{
      already_existing_id1: already_existing_id1
    } do
      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe(Thing, :updated)
      end

      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe(Thing, :updated, already_existing_id1)
      end

      assert_raise RuntimeError, ~r/EctoWatch is not running/, fn ->
        EctoWatch.subscribe(Thing, :updated, {:parent_thing_id, already_existing_id1})
      end
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
                   ~r/No watcher found for NotASchema \/ :updated/,
                   fn ->
                     EctoWatch.subscribe(NotASchema, :updated)
                   end

      assert_raise ArgumentError,
                   ~r/No watcher found for NotASchema \/ :updated/,
                   fn ->
                     EctoWatch.subscribe(NotASchema, :updated, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   ~r/No watcher found for NotASchema \/ :updated/,
                   fn ->
                     EctoWatch.subscribe(
                       NotASchema,
                       :updated,
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
                     EctoWatch.subscribe(Thing, :something_else)
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: 1234.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, 1234)
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, :something_else, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: 1234.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, 1234, already_existing_id1)
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: :something_else.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(
                       Thing,
                       :something_else,
                       {:parent_thing_id, already_existing_id1}
                     )
                   end

      assert_raise ArgumentError,
                   "Unexpected update_type: 1234.  Expected :inserted, :updated, or :deleted",
                   fn ->
                     EctoWatch.subscribe(Thing, 1234, {:parent_thing_id, already_existing_id1})
                   end
    end
  end

  describe "inserts" do
    test "get notification about inserts" do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted},
           {Other, :inserted}
         ]}
      )

      EctoWatch.subscribe(Thing, :inserted)
      EctoWatch.subscribe(Other, :inserted)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, the_float, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (1234, 'the value', NOW(), NOW())",
        []
      )

      assert_receive {:inserted, Thing, %{id: 3}}
      assert_receive {:inserted, Other, %{weird_id: 1234}}
    end

    test "inserts for an association column", %{already_existing_id2: already_existing_id2} do
      start_supervised!(
        {EctoWatch,
         repo: TestRepo,
         pub_sub: TestPubSub,
         watchers: [
           {Thing, :inserted, extra_columns: [:parent_thing_id]}
         ]}
      )

      EctoWatch.subscribe(Thing, :inserted, {:parent_thing_id, already_existing_id2})

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO things (the_string, the_integer, the_float, parent_thing_id, extra_field, inserted_at, updated_at) VALUES ('the other value', 8900, 24.53, #{already_existing_id2}, 'hey', NOW(), NOW())",
        []
      )

      assert_receive {:inserted, Thing, %{id: 3, parent_thing_id: ^already_existing_id2}}
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
                       Thing,
                       :inserted,
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
                     EctoWatch.subscribe(Thing, :inserted, {:the_string, "test"})
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
        "INSERT INTO things (the_string, the_integer, the_float, inserted_at, updated_at) VALUES ('the value', 4455, 84.52, NOW(), NOW())",
        []
      )

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "INSERT INTO \"0xabcd\".other (weird_id, the_string, inserted_at, updated_at) VALUES (4321, 'the value', NOW(), NOW())",
        []
      )

      refute_receive {:inserted, Thing, %{}}
      refute_receive {:inserted, Other, %{}}
    end
  end

  describe "updated" do
    test "all updates", %{
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

      EctoWatch.subscribe(Thing, :updated)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {:updated, Thing, %{id: ^already_existing_id1}}

      assert_receive {:updated, Thing, %{id: ^already_existing_id2}}
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

      EctoWatch.subscribe(Thing, :updated, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      assert_receive {:updated, Thing, %{id: ^already_existing_id1}}

      refute_receive {:updated, Thing, %{id: ^already_existing_id2}}
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
           {Thing, :updated, extra_columns: [:parent_thing_id]}
         ]}
      )

      EctoWatch.subscribe(Thing, :updated, {:parent_thing_id, already_existing_id1})

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {:updated, Thing, %{id: ^already_existing_id1}}

      assert_receive {:updated, Thing,
                      %{id: ^already_existing_id2, parent_thing_id: ^already_existing_id1}}
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
                       Thing,
                       :updated,
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
                     EctoWatch.subscribe(Thing, :updated, {:the_string, "test"})
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

      EctoWatch.subscribe(:thing_custom_event, :updated, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {:updated, _, %{id: ^already_existing_id1}}
      refute_receive {:updated, _, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9999", [])

      assert_receive {:updated, :thing_custom_event, %{id: ^already_existing_id1}}
      refute_receive {:updated, _, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_float = 99.999", [])

      assert_receive {:updated, :thing_custom_event, %{id: ^already_existing_id1}}
      refute_receive {:updated, _, %{id: ^already_existing_id2}}
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

      EctoWatch.subscribe(Thing, :updated, already_existing_id1)

      Ecto.Adapters.SQL.query!(
        TestRepo,
        "UPDATE things SET the_string = 'the new value' WHERE id = $1",
        [already_existing_id1]
      )

      assert_receive {:updated, Thing,
                      %{id: ^already_existing_id1, the_integer: 4455, the_float: 84.52}}

      refute_receive {:updated, _, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_integer = 9999 WHERE id = $1", [
        already_existing_id1
      ])

      assert_receive {:updated, Thing,
                      %{id: ^already_existing_id1, the_integer: 9999, the_float: 84.52}}

      refute_receive {:updated, _, %{id: ^already_existing_id2}}

      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_float = 99.999 WHERE id = $1", [
        already_existing_id1
      ])

      assert_receive {:updated, Thing,
                      %{id: ^already_existing_id1, the_integer: 9999, the_float: 99.999}}

      refute_receive {:updated, _, %{id: ^already_existing_id2}}
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "UPDATE things SET the_string = 'the new value'", [])

      refute_receive {:updated, Thing, %{id: ^already_existing_id1}}

      refute_receive {:updated, Thing, %{id: ^already_existing_id2}}
    end
  end

  describe "deleted" do
    test "all deletes", %{
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

      EctoWatch.subscribe(Thing, :deleted)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {:deleted, Thing, %{id: ^already_existing_id1}}

      assert_receive {:deleted, Thing, %{id: ^already_existing_id2}}
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

      EctoWatch.subscribe(Thing, :deleted, already_existing_id1)

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      assert_receive {:deleted, Thing, %{id: ^already_existing_id1}}

      refute_receive {:deleted, Thing, %{id: ^already_existing_id2}}
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
           {Thing, :deleted, extra_columns: [:parent_thing_id]}
         ]}
      )

      EctoWatch.subscribe(Thing, :deleted, {:parent_thing_id, already_existing_id1})

      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {:deleted, Thing, %{id: ^already_existing_id1}}

      assert_receive {:deleted, Thing,
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
                       Thing,
                       :deleted,
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
                     EctoWatch.subscribe(Thing, :deleted, {:the_string, "test"})
                   end
    end

    test "no notifications without subscribe", %{
      already_existing_id1: already_existing_id1,
      already_existing_id2: already_existing_id2
    } do
      Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM things", [])

      refute_receive {:deleted, Thing, %{id: ^already_existing_id1}}

      refute_receive {:deleted, Thing, %{id: ^already_existing_id2}}
    end
  end
end
