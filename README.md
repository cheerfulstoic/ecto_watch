# EctoWatch

<sub>(Thanks to [Erlang Solutions](https://www.erlang-solutions.com) for sponsoring this project)</sub>

[HexDocs documentation](https://hexdocs.pm/ecto_watch)

EctoWatch allows you to easily setup notifications of database changes *directly* from PostgreSQL.

Often in Elixir applications a `Phoenix.PubSub.broadcast` is inserted into the application code to notify the rest of the application about inserts, updates, or deletions (e.g. `Accounts.insert_user`/`Accounts.update_user`/`Accounts.delete_user`).  This has a few potential problems:

 * Developers may forget to call these functions and make updates directly through `MyApp.Repo.*`.
 * Often different standards of PubSub messages are used. [^1]
 * Often full records are used which can scale poorly since messages in Elixir are copied in memory when sent.
 * Sometimes records are sent preloaded with different associations in different cases, requiring either careful coordination or sending all associations regardless of where they are needed.

By getting updates directly from PostgreSQL, EctoWatch ensures that messages are sent for *every* change (even changes from other clients of the database).  EctoWatch also establishes a simple, standardized set of messages for inserts, updates, and deletes so that there can be consistency across your application.  By default only the id of the record is sent (makeing for smaller messages).

## Example use-cases for `EctoWatch`

 * Updating LiveView in real-time
 * Sending emails when a record is updated
 * Updating a cache when a record is updated
 * Sending a webhook request to inform another system about a change

## Usage

To use EctoWatch, you need to add it to your supervision tree and specify watchers for Ecto schemas and update types.  It would look something like this in your `application.ex` file (after `MyApp.Repo` and `MyApp.PubSub`):

```elixir
  alias MyApp.Accounts.User
  alias MyApp.Accounts.Package

  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     {User, :inserted},
     {User, :updated},
     {User, :deleted},
     {Package, :inserted},
     {Package, :updated}
   ]}
```

This will setup:

 * triggers in PostgreSQL during application startup
 * an Elixir process for each watcher which listens for notifications and broadcasts them via `Phoenix.PubSub`

Then any process (e.g. a GenServer, a LiveView, a Phoenix channel, etc...) can subscribe to messages like so:

```elixir
  EctoWatch.subscribe({User, :inserted})
  EctoWatch.subscribe({User, :updated})
  EctoWatch.subscribe({User, :deleted})

  EctoWatch.subscribe({Package, :inserted})
  EctoWatch.subscribe({Package, :updated})
```

(note that if you are subscribing in a LiveView `mount` callback you should subscribe inside of a `if connected?(socket) do` to avoid subscribing twice).

You can also subscribe to individual records:

```elixir
  EctoWatch.subscribe({User, :updated}, user.id)
  EctoWatch.subscribe({User, :deleted}, user.id)
```

... OR you can subscribe to records by an association column (but the given column must be in the `extra_columns` list for the watcher! See below for more info on the `extra_columns` option):

```elixir
  EctoWatch.subscribe({User, :updated}, {:role_id, role.id})
  EctoWatch.subscribe({User, :deleted}, {:role_id, role.id})
```

Once subscribed, messages can be handled like so (LiveView example are given here but `handle_info` callbacks can be used elsewhere as well):

```elixir
  def handle_info({{User, :inserted}, %{id: id}}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({{User, :updated}, %{id: id}}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({{User, :deleted}, %{id: id}}, socket) do
    socket = stream_delete_by_dom_id(socket, :songs, "users-#{id}")

    {:noreply, socket}
  end
```

There are a lot of features to check out!  Check out the [HexDocs documentation](https://hexdocs.pm/ecto_watch) for all of the details!

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecto_watch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_watch, "~> 0.8.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ecto_watch>.

[^1]: more info about PubSub message standards:
  - Having a single topic (e.g. `users`) means that all messages are sent to all subscribers, which can be inefficient.
  - Having a topic per record (e.g. `users:1`, `users:2`, etc.) means that a subscriber needs to subscribe to every record, which can be inefficient.
  - There may be inconsistancy in pluralization of topics (e.g. a `user` vs. `packages` topics) which can be confusing and lead to bugs.
  - Having a message that is just `{:updated, id}` doesn't make it clear which schema was updated, using `{schema, id}` doesn't make it clear which operation happened.
