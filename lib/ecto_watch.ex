defmodule EctoWatch do
  use GenServer

  def subscribe(schema_mod, type, id \\ nil) do
    pubsub_mod = GenServer.call(__MODULE__, :get_pubsub_mod)

    case type do
      :inserted ->
        if(id, do: raise("Cannot subscribe to id for inserted records"))

        Phoenix.PubSub.subscribe(
          pubsub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:inserts"
        )

      :updated ->
        if id do
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:updates:#{id}"
          )
        else
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:updates"
          )
        end

      :deleted ->
        if id do
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:deletes:#{id}"
          )
        else
          Phoenix.PubSub.subscribe(
            pubsub_mod,
            "ecto_watch:#{schema_mod.__schema__(:source)}:deletes"
          )
        end

      other ->
        raise ArgumentError,
              "Unexpected subscription event: #{inspect(other)}.  Expected :inserted, :updated, or :deleted"
    end
  end

  def start_link(opts) do
    case EctoWatch.Options.validate(opts) do
      {:ok, validated_opts} ->
        GenServer.start_link(__MODULE__, validated_opts, name: __MODULE__)

      {:error, errors} ->
        raise ArgumentError, "Invalid options: #{Exception.message(errors)}"
    end
  end

  def init(opts) do
    # TODO:
    # Allow passing in options specific to Postgrex.Notifications.start_link/1
    # https://hexdocs.pm/postgrex/Postgrex.Notifications.html#start_link/1
    options = EctoWatch.Options.new(opts)

    {:ok, notifications_pid} = Postgrex.Notifications.start_link(options.repo_mod.config())

    schema_mods_by_channel =
      Map.new(options.watchers, fn watcher ->
        table_name = watcher.schema_mod.__schema__(:source)
        # channel_name = channel_name(schema_mod)
        channel_name = "ecto_watch_#{table_name}_changed"

        function_name = "ecto_watch_#{table_name}_notify_#{watcher.update_type}"

        update_keyword =
          case watcher.update_type do
            :inserted -> "INSERT"
            :updated -> "UPDATE"
            :deleted -> "DELETE"
          end

        Ecto.Adapters.SQL.query!(
          options.repo_mod,
          """
          CREATE OR REPLACE FUNCTION #{function_name}()
            RETURNS trigger AS $trigger$
            DECLARE
              payload TEXT;
            BEGIN
              payload := jsonb_build_object('type','#{watcher.update_type}','id',COALESCE(OLD.id, NEW.id));
              PERFORM pg_notify('#{channel_name}', payload);

              RETURN NEW;
            END;
            $trigger$ LANGUAGE plpgsql;
          """,
          []
        )

        Ecto.Adapters.SQL.query!(
          options.repo_mod,
          """
          CREATE OR REPLACE TRIGGER ecto_watch_#{table_name}_#{watcher.update_type}_trigger
            AFTER #{update_keyword} ON #{table_name} FOR EACH ROW
            EXECUTE PROCEDURE #{function_name}();
          """,
          []
        )

        {channel_name, watcher.schema_mod}
      end)

    options.watchers
    |> Enum.map(& &1.schema_mod.__schema__(:source))
    |> Enum.uniq()
    |> Enum.each(fn table_name ->
      channel_name = "ecto_watch_#{table_name}_changed"

      {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, channel_name)
    end)

    {:ok,
     %{
       options: options,
       schema_mods_by_channel: schema_mods_by_channel
     }}
  end

  def handle_call(:get_pubsub_mod, _from, state) do
    {:reply, state.options.pub_sub_mod, state}
  end

  def handle_info({:notification, _pid, _ref, channel, payload}, state) do
    schema_mod = Map.get(state.schema_mods_by_channel, channel)

    data = Jason.decode!(payload)
    id = data["id"]

    case data["type"] do
      "inserted" ->
        Phoenix.PubSub.broadcast(
          state.options.pub_sub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:inserts",
          {:inserted, schema_mod, id}
        )

      "updated" ->
        Phoenix.PubSub.broadcast(
          state.options.pub_sub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:updates",
          {:updated, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.options.pub_sub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:updates:#{id}",
          {:updated, schema_mod, id}
        )

      "deleted" ->
        Phoenix.PubSub.broadcast(
          state.options.pub_sub_mod,
          "ecto_watch:#{schema_mod.__schema__(:source)}:deletes",
          {:deleted, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.options.pub_sub_mod,
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
