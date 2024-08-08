You can also setup the database to trigger only on specific column changes on `:updated` watchers.  When doing this a `label` required:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {User, :updated, trigger_columns: [:email, :phone], label: :user_contact_info_updated},
     # ...
   ]}

  # subscribing
  EctoWatch.subscribe(:user_contact_info_updated)
  # or...
  EctoWatch.subscribe(:user_contact_info_updated, package.id)

  # handling messages
  def handle_info({:user_contact_info_updated, %{id: id}}, socket) do
```

A label is required for two reasons:

 * When handling the message it makes it clear that the message isn't for general schema updates but is for specific columns
 * The same schema can be watched for different sets of columns, so the label is used to differentiate between them.

You can also use labels in general without tracking specific columns:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {User, :updated, label: :user_update},
     # ...
   ]}

  # subscribing
  EctoWatch.subscribe(:user_update)
  # or...
  EctoWatch.subscribe(:user_update, package.id)

  # handling messages
  def handle_info({:user_update, %{id: id}}, socket) do
```

