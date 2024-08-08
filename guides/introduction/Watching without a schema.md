Since ecto supports working with tables withoun needed a schema, you may also want to create EctoWatch watchers without needing to create a schema like so:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
    {
      %{
        table_name: "comments",
        primary_key: :ID,
        columns: [:title, :body, :author_id, :post_id],
        association_columns: [:author_id, :post_id]
      }, :updated, extra_columns: [:post_id]
    }
   ]}
```

Everything works the same as with a schema, though make sure to specify your association columns if you want to subscribe to an association column.

Supported keys for configuring a table without a schema:

 * `schema_prefix` (optional, defaults to `public`)
 * `table_name` (required)
 * `primary_key` (optional, defaults to `id`)
 * `columns` (optional, defaults to `[]`)
 * `association_columns` (optional, defaults to `[]`)

