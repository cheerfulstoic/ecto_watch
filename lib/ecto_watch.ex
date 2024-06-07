defmodule EctoWatch do
  use GenServer

  def subscribe(schema_mod, type, id \\ nil) do
    pubsub_mod = GenServer.call(__MODULE__, :get_pubsub_mod)

    case type do
      :inserted ->
        if(id, do: raise("Cannot subscribe to id for inserted records"))

        Phoenix.PubSub.subscribe(pubsub_mod, "ecto_watch:#{schema_mod.__schema__(:source)}:inserts")

      :updated ->
        if id do
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:updates:#{id}"
          )
        else
          Phoenix.PubSub.subscribe(pubsub_mod, "ecto_watch:#{schema_mod.__schema__(:source)}:updates")
        end

      :deleted ->
        if id do
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:deletes:#{id}"
          )
        else
          Phoenix.PubSub.subscribe(pubsub_mod, "ecto_watch:#{schema_mod.__schema__(:source)}:deletes")
        end

      other ->
        raise ArgumentError,
              "Unexpected subscription event: #{inspect(other)}.  Expected :inserted, :updated, or :deleted"
    end
  end

  def start_link({repo, pubsub_mod, schema_mods}) do
    GenServer.start_link(__MODULE__, {repo, pubsub_mod, schema_mods}, name: __MODULE__)
  end

  def init({repo, pubsub_mod, schema_mods}) do
    # TODO:
    # Allow passing in options specific to Postgrex.Notifications.start_link/1
    # https://hexdocs.pm/postgrex/Postgrex.Notifications.html#start_link/1
    {:ok, notifications_pid} = Postgrex.Notifications.start_link(repo.config())
    Enum.each(schema_mods, &setup_for_schema_mod(repo, &1, notifications_pid))

    schema_mods_by_channel =
      Map.new(schema_mods, fn schema_mod ->
        {channel_name(schema_mod), schema_mod}
      end)

    {:ok,
     %{
       repo: repo,
       pubsub_mod: pubsub_mod,
       schema_mods_by_channel: schema_mods_by_channel
     }}
  end

  def handle_call(:get_pubsub_mod, _from, state) do
    {:reply, state.pubsub_mod, state}
  end

  def handle_info({:notification, _pid, _ref, channel, payload}, state) do
    schema_mod = Map.get(state.schema_mods_by_channel, channel)

    data = Jason.decode!(payload)
    id = data["id"]

    case data["type"] do
      "insert" ->
        Phoenix.PubSub.broadcast(
          state.pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:inserts",
          {:inserted, schema_mod, id}
        )

      "update" ->
        Phoenix.PubSub.broadcast(
          state.pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:updates",
          {:updated, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:updates:#{id}",
          {:updated, schema_mod, id}
        )

      "delete" ->
        Phoenix.PubSub.broadcast(
          state.pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:deletes",
          {:deleted, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:deletes:#{id}",
          {:deleted, schema_mod, id}
        )
    end

    {:noreply, state}
  end

  # payload := json_build_object('id',OLD.id,'old',row_to_json(OLD),'new',row_to_json(NEW));
  defp setup_for_schema_mod(repo, schema_mod, notifications_pid) do
    table_name = schema_mod.__schema__(:source)
    channel_name = channel_name(schema_mod)

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE FUNCTION ecto_watch_#{table_name}_notify_inserted()
        RETURNS trigger AS $trigger$
        DECLARE
          payload TEXT;
        BEGIN
          payload := jsonb_build_object('type','insert','id',NEW.id);
          PERFORM pg_notify('#{channel_name}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE FUNCTION ecto_watch_#{table_name}_notify_updated()
        RETURNS trigger AS $trigger$
        DECLARE
          payload TEXT;
        BEGIN
          payload := jsonb_build_object('type','update','id',OLD.id);
          PERFORM pg_notify('#{channel_name}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE FUNCTION ecto_watch_#{table_name}_notify_deleted()
        RETURNS trigger AS $trigger$
        DECLARE
          payload TEXT;
        BEGIN
          payload := jsonb_build_object('type','delete','id',OLD.id);
          PERFORM pg_notify('#{channel_name}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE TRIGGER ecto_watch_#{table_name}_inserted_trigger
        AFTER INSERT ON #{table_name} FOR EACH ROW
        EXECUTE PROCEDURE ecto_watch_#{table_name}_notify_inserted();
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE TRIGGER ecto_watch_#{table_name}_updated_trigger
        AFTER UPDATE ON #{table_name} FOR EACH ROW
        EXECUTE PROCEDURE ecto_watch_#{table_name}_notify_updated();
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo,
      """
      CREATE OR REPLACE TRIGGER ecto_watch_#{table_name}_deleted_trigger
        AFTER DELETE ON #{table_name} FOR EACH ROW
        EXECUTE PROCEDURE ecto_watch_#{table_name}_notify_deleted();
      """,
      []
    )

    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, channel_name)
  end

  def channel_name(schema_mod) do
    "ecto_watch_#{schema_mod.__schema__(:source)}_changed"
  end
end
