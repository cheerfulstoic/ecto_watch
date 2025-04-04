Getting Started

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

**NOTE:** you can't subscribe to the `:inserted` event for specific objects because the primary key's value which you would use to subscribe doesn't exist until the insert happens.

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
