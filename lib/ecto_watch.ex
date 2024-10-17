defmodule EctoWatch do
  @moduledoc """
  A library to allow you to easily get notifications about database changes directly from PostgreSQL.
  """

  alias EctoWatch.Helpers
  alias EctoWatch.WatcherServer
  alias EctoWatch.WatcherTriggerValidator

  use Supervisor

  def start_link(opts) do
    case EctoWatch.Options.validate(opts) do
      {:ok, validated_opts} ->
        options = EctoWatch.Options.new(validated_opts)

        validate_watcher_uniqueness(options.watchers)

        Supervisor.start_link(__MODULE__, options, name: __MODULE__)

      {:error, errors} ->
        raise ArgumentError, "Invalid options: #{Exception.message(errors)}"
    end
  end

  def init(options) do
    # TODO:
    # Allow passing in options specific to Postgrex.Notifications.start_link/1
    # https://hexdocs.pm/postgrex/Postgrex.Notifications.html#start_link/1

    postgrex_notifications_options =
      options.repo_mod.config()
      |> Keyword.put(:name, :ecto_watch_postgrex_notifications)

    children = [
      {Postgrex.Notifications, postgrex_notifications_options},
      {EctoWatch.WatcherSupervisor, options},
      {WatcherTriggerValidator, nil}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @deprecated "subscribe/3 was removed in version 0.8.0. See the updated documentation"
  def subscribe(schema_mod_or_label, update_type, id) when is_atom(schema_mod_or_label) do
    if Helpers.ecto_schema_mod?(schema_mod_or_label) do
      raise ArgumentError,
            """
            This way of subscribing was removed in version 0.8.0. Instead call:

            subscribe({#{inspect(schema_mod_or_label)}, #{inspect(update_type)}}, #{id})

            IMPORTANT NOTE: The messages that you receive have also changed!

            Before:

              # labels:
              def handle_info({:updated, User, %{id: id}}, socket) do
              # schemas:
              def handle_info({:user_contact_info_updated, :updated, %{id: id}}, socket) do

            Now:

              # labels:
              def handle_info({{User, :updated}, %{id: id}}, socket) do
              # schemas:
              def handle_info({:user_contact_info_updated, %{id: id}}, socket) do

            PLEASE NOTE the flipped order of `User` and `:updated` in the tuple!

            See the updated documentation for subscribing."
            """
    else
      raise ArgumentError,
            """
            This way of subscribing was removed in version 0.8.0. Instead call:

            subscribe(#{inspect(schema_mod_or_label)}, #{id})

            Before:

              # labels:
              def handle_info({:updated, User, %{id: id}}, socket) do
              # schemas:
              def handle_info({:user_contact_info_updated, :updated, %{id: id}}, socket) do

            Now:

              # labels:
              def handle_info({{User, :updated}, %{id: id}}, socket) do
              # schemas:
              def handle_info({:user_contact_info_updated, %{id: id}}, socket) do

            PLEASE NOTE the flipped order of `User` and `:updated` in the tuple!

            See the updated documentation for subscribing."
            """
    end
  end

  @type watcher_identifier() :: {atom(), atom()} | atom()

  @doc """
  Subscribe to notifications from watchers.

  Examples:

      iex> EctoWatch.subscribe({Comment, :updated})

    When subscribing to a watcher with the `label` option specified as `:comment_updated_custom`:

      iex> EctoWatch.subscribe(:comment_updated_custom)

    You can subscribe to notifications just from specific primary key values:

      iex> EctoWatch.subscribe({Comment, :updated}, user_id)

    Or you can subscribe to notifications just from a specific foreign column (**the column must be in the watcher's `extra_columns` list):

      iex> EctoWatch.subscribe({Comment, :updated}, {:post_id, post_id})
  """
  @spec subscribe(watcher_identifier(), term()) :: :ok | {:error, term()}
  def subscribe(watcher_identifier, id \\ nil) do
    if is_atom(watcher_identifier) && id in ~w[inserted updated deleted]a do
      if Helpers.ecto_schema_mod?(watcher_identifier) do
        raise ArgumentError,
              """
              This way of subscribing was removed in version 0.8.0. Instead call:

              subscribe({#{inspect(watcher_identifier)}, #{inspect(id)}})

              Before:

                # labels:
                def handle_info({:updated, User, %{id: id}}, socket) do
                # schemas:
                def handle_info({:user_contact_info_updated, :updated, %{id: id}}, socket) do

              Now:

                # labels:
                def handle_info({{User, :updated}, %{id: id}}, socket) do
                # schemas:
                def handle_info({:user_contact_info_updated, %{id: id}}, socket) do

              PLEASE NOTE the flipped order of `User` and `:updated` in the tuple!

              See the updated documentation for subscribing."
              """
      else
        raise ArgumentError,
              """
              This way of subscribing was removed in version 0.8.0. Instead call:

              subscribe(#{inspect(watcher_identifier)})

              Before:

                # labels:
                def handle_info({:updated, User, %{id: id}}, socket) do
                # schemas:
                def handle_info({:user_contact_info_updated, :updated, %{id: id}}, socket) do

              Now:

                # labels:
                def handle_info({{User, :updated}, %{id: id}}, socket) do
                # schemas:
                def handle_info({:user_contact_info_updated, %{id: id}}, socket) do

              PLEASE NOTE the flipped order of `User` and `:updated` in the tuple!

              See the updated documentation for subscribing."
              """
      end
    end

    validate_ecto_watch_running!()

    with :ok <- validate_identifier(watcher_identifier),
         {:ok, {pub_sub_mod, channel_name, debug?}} <-
           WatcherServer.pub_sub_subscription_details(watcher_identifier, id) do
      if(debug?, do: debug_log(watcher_identifier, "Subscribing to watcher"))

      Phoenix.PubSub.subscribe(pub_sub_mod, channel_name)
    else
      {:error, error} ->
        raise ArgumentError, error
    end
  end

  @doc """
  Unsubscribe to notifications from watchers that you previously subscribe. It
  receives the same params for `subscribe/2`.

  Examples:

      iex> EctoWatch.unsubscribe({Comment, :updated})
      iex> EctoWatch.unsubscribe({Comment, :updated}, {:post_id, post_id})
  """
  @spec unsubscribe(watcher_identifier(), term()) :: :ok | {:error, term()}
  def unsubscribe(watcher_identifier, id \\ nil) do
    validate_ecto_watch_running!()

    with :ok <- validate_identifier(watcher_identifier),
         {:ok, {pub_sub_mod, channel_name, debug?}} <-
           WatcherServer.pub_sub_subscription_details(watcher_identifier, id) do
      if(debug?, do: debug_log(watcher_identifier, "Unsubscribing to watcher"))

      Phoenix.PubSub.unsubscribe(pub_sub_mod, channel_name)
    else
      {:error, error} ->
        raise ArgumentError, error
    end
  end

  @doc """
  Returns details about a watcher for reflection purposes

  For example if you need to know what the function/triggers are in the database.

  Examples:

      iex> EctoWatch.subscribe({Comment, :updated})

    Or for a label:

      iex> EctoWatch.subscribe(:comment_updated_custom)
  """
  @spec details(watcher_identifier()) :: %{
          repo_mod: module(),
          schema_definition: %{
            schema_prefix: binary(),
            table_name: binary(),
            primary_key: binary(),
            columns: [atom()],
            association_columns: [atom()],
            label: term()
          },
          function_name: binary(),
          trigger_name: binary(),
          notify_channel: binary()
        }
  def details(watcher_identifier) do
    WatcherServer.details(watcher_identifier)
  end

  defp validate_identifier({schema_mod, update_type})
       when is_atom(schema_mod) and is_atom(update_type) do
    cond do
      !EctoWatch.Helpers.ecto_schema_mod?(schema_mod) ->
        raise ArgumentError,
              "Expected atom to be an Ecto schema module. Got: #{inspect(schema_mod)}"

      update_type not in ~w[inserted updated deleted]a ->
        raise ArgumentError,
              "Unexpected update_type: #{inspect(update_type)}.  Expected :inserted, :updated, or :deleted"

      true ->
        :ok
    end
  end

  defp validate_identifier(label) when is_atom(label) do
    :ok
  end

  defp validate_identifier(other) do
    raise ArgumentError,
          "Invalid subscription (expected either `{schema_module, :inserted | :updated | :deleted}` or a label): #{inspect(other)}"
  end

  defp validate_ecto_watch_running! do
    if !Process.whereis(__MODULE__) do
      raise "EctoWatch is not running. Please start it by adding it to your supervision tree or using EctoWatch.start_link/1"
    end
  end

  defp validate_watcher_uniqueness(watcher_options) do
    {without_labels, with_labels} = Enum.split_with(watcher_options, &(&1.label == nil))

    duplicate_labels =
      with_labels
      |> Enum.map(& &1.label)
      |> duplicate_values()

    duplicate_schema_and_update_types =
      without_labels
      |> Enum.map(&{&1.schema_definition.label, &1.update_type})
      |> duplicate_values()

    error_messages =
      [
        if length(duplicate_labels) > 0 do
          """
          The following labels are duplicated across watchers: #{Enum.join(duplicate_labels, ", ")}
          """
        end,
        if length(duplicate_schema_and_update_types) > 0 do
          """
          The following schema and update type combinations are duplicated across watchers:

            #{Enum.map_join(duplicate_schema_and_update_types, "\n\n  ", &inspect/1)}
          """
        end
      ]
      |> Enum.reject(&is_nil/1)

    if length(error_messages) > 0 do
      raise ArgumentError, Enum.join(error_messages, "\n")
    end
  end

  defp duplicate_values(values) do
    values
    |> Enum.group_by(&Function.identity/1)
    |> Enum.filter(fn {_, values} -> length(values) >= 2 end)
    |> Enum.map(fn {_, [value | _]} -> value end)
  end

  defp debug_log(watcher_identifier, message) do
    EctoWatch.Helpers.debug_log(watcher_identifier, message)
  end
end
