defmodule EctoWatch do
  @moduledoc false

  alias EctoWatch.WatcherServer
  alias EctoWatch.Helpers

  use Supervisor

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

            See the updated documentation for subscribing."
            """
    end
  end

  def subscribe(identifier, id \\ nil) do
    if is_atom(identifier) && id in ~w[inserted updated deleted]a do
      if Helpers.ecto_schema_mod?(identifier) do
        raise ArgumentError,
              """
              This way of subscribing was removed in version 0.8.0. Instead call:

              subscribe({#{inspect(identifier)}, #{inspect(id)}})

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

              See the updated documentation for subscribing."
              """
      else
        raise ArgumentError,
              """
              This way of subscribing was removed in version 0.8.0. Instead call:

              subscribe(#{inspect(identifier)})

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

              See the updated documentation for subscribing."
              """
      end
    end

    validate_ecto_watch_running!()

    with :ok <- validate_identifier(identifier),
         {:ok, {pub_sub_mod, channel_name}} <-
           WatcherServer.pub_sub_subscription_details(identifier, id) do
      Phoenix.PubSub.subscribe(pub_sub_mod, channel_name)
    else
      {:error, error} ->
        raise ArgumentError, error
    end
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

  def start_link(opts) do
    case EctoWatch.Options.validate(opts) do
      {:ok, validated_opts} ->
        options = EctoWatch.Options.new(validated_opts)

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
      {EctoWatch.WatcherSupervisor, options}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
