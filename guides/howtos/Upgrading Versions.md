As `EctoWatch` is pre-1.0.0, breaking changes may occur in minor versions. This guide is here to help you understand version releases with breaking changes and how to change your code to work with the new version.

## Upgrading to 0.6.0

In this version the broadcast messages from `EctoWatch` changed from a 4-element tuple to a 3-element tuple. Before the primary key value and the `extra_columns` data were two separate elements in the tuple:

```elixir
def handle_info({:inserted, Comment, id, %{post_id: post_id}}, socket) do
  # ...
```

With version 0.6.0, they are combined into a single map:

```elixir
def handle_info({:inserted, Comment, %{id: id, post_id: post_id}}, socket) do
  # ...
```

## Upgrading to 0.8.0

In this version became is no longer required to specify the update type (`:inserted`/`:updated`/`:deleted`) for watchers with labels.  Before you would have:

```elixir
# watcher config:
watchers: [
  {Comment, :updated, trigger_columns: [:title, :body], label: :title_or_body_updated},

# subscribe:
EctoWatch.subscribe(:title_or_body_updated, :updated)
# or
EctoWatch.subscribe(:title_or_body_updated, :updated, comment_id)
# or
EctoWatch.subscribe(:title_or_body_updated, :updated, {:post_id, post_id})

# handler:
def handle_info({:inserted, Comment, %{id: id}}, socket) do
  # ...
```

With versios 0.8.0 the update type is implied by the label, so you can subscribe simply by doing:

```elixir
# subscribe:
EctoWatch.subscribe(:title_or_body_updated)
# or
EctoWatch.subscribe(:title_or_body_updated, comment_id)
# or
EctoWatch.subscribe(:title_or_body_updated, {:post_id, post_id})
```

Also, to keep the subscribe function consistent, the normal case of subscribing and handling to a watcher that doesn't have a label requires a tuple of the ecto schema + update type:

```elixir
# watcher config:
watchers: [
  {Comment, :updated},

EctoWatch.subscribe({Comment, :updated})

# handler (NOTE the flipped order of schema and update type):
def handle_info({{Comment, :inserted}, %{id: id}}, socket) do
  # ...
```

You can think of the first argument of `subscribe` or the first element of the tuple as an lookup identifier for the watcher which is either `{ecto_schema(), update_type()}` or a label atom.  So handling a label would just be:


```elixir
def handle_info({:title_or_body_updated, %{id: id}}, socket) do
  # ...
```

