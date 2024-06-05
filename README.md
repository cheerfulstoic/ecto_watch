# EctoWatch

EctoWatch allows you to easily get Phoenix.PubSub notifications *directly* from postgresql.

Often in Elixir applications a `Phoenix.PubSub.broadcast` is sent to notifiy other parts of the application that an insert, update, or deletion has occurred.  This has a few problems:

 * All application code must use the same function(s) which send broadcasts (i.e. rather than making updates themselves)
 * The messages which are sent out may vary if a standard isnt' established
 * Often full records are sent which can scale poorly since messages in Elixir are copied in memory when sent
 * Sometimes records are sent pre-loaded with different associations, requiring either careful coordination or a sending of all associations regardless of where they are needed

EctoWatch solves these problems by getting updates directly from postgresql.  This ensures that messages are sent for every update.  EctoWatch also establishes a simple standardized set of messages for inserts, updates, and deletes so that there can be consistency across your application.

## Usage

To use EctoWatch, you need to add it to your supervision tree and specify the ecto schemas that you want to monitor.  You can do this by adding something like the following to your `application.ex` file (after your `MyApp.Repo` and `MyApp.PubSub` are loaded):

```elixir
  {EctoWatch, {MyApp.Repo, MyApp.PubSub, [
    MyApp.Accounts.User,
    MyApp.Shipping.Package
  ]}},
```

This will setup:

 * triggers in postgresql on startup
 * a process which listens for notifications and broadcasts them via `Phoenix.PubSub`

Then any process (e.g. a GenServer, a LiveView, or a Phoenix channel) can subscribe to messages like so:

```elixir
  EctoWatch.subscribe(MyApp.Accounts.User, :inserted)
  EctoWatch.subscribe(MyApp.Accounts.User, :updated)
  EctoWatch.subscribe(MyApp.Accounts.User, :deleted)

  EctoWatch.subscribe(MyApp.Shipping.Package, :inserted)
  EctoWatch.subscribe(MyApp.Shipping.Package, :updated)
```

(note that if you are subscribing in a LiveView `mount` callback you should subscribe inside of a `if connected?(socket) do` block to avoid subscribing twice).

You can also subscribe to individual records:

```elixir
  EctoWatch.subscribe(MyApp.Accounts.User, :updated, user.id)
  EctoWatch.subscribe(MyApp.Accounts.User, :deleted, user.id)
```

Once a process is subscribed messages can be handled like so (LiveView example given here but `handle_info` callbacks can be used elsewhere as well):


```elixir
  def handle_info({:inserted, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({:updated, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({:deleted, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_delete(socket, :users, user)

    {:noreply, socket}
  end
```


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecto_watch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_watch, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ecto_watch>.

