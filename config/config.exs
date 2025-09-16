import Config

config :ecto_watch, EctoWatch.DB, mod: EctoWatch.DB.Live

if Mix.env() == :test do
  config :ecto_watch, EctoWatch.DB, mod: EctoWatch.DB.Mock
end
