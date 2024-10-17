## Unsubscribing

To unsubscribe, you can simply use the schema/type or the label in the same way that you did for subscribing.  So if you subscribe like so:

```elixir
EctoWatch.subscribe({User, :inserted})

EctoWatch.subscribe({User, :updated}, {:role_id, role.id})

EctoWatch.subscribe(:user_contact_info_updated)
```

You can unsubscribe like so (respectively):

```elixir
EctoWatch.unsubscribe({User, :inserted})

EctoWatch.unsubscribe({User, :updated}, {:role_id, role.id})

EctoWatch.unsubscribe(:user_contact_info_updated)
```
