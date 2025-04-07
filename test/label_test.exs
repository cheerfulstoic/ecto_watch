defmodule EctoWatch.LabelTest do
  use ExUnit.Case
  alias EctoWatch.Label

  defmodule Thing do
    use Ecto.Schema

    schema "things" do
      field(:the_string, :string)
    end
  end

  test "atom + update_type" do
    assert Label.unique_label({MyApp.One, :updated}) == :"ew_u_for_Elixir.MyApp.One"
    assert Label.unique_label({MyApp.One, :deleted}) == :"ew_d_for_Elixir.MyApp.One"
    assert Label.unique_label({MyApp.One, :inserted}) == :"ew_i_for_Elixir.MyApp.One"

    assert Label.unique_label({:some_topic, :updated}) == :ew_u_for_some_topic
    assert Label.unique_label({:some_topic, :deleted}) == :ew_d_for_some_topic
    assert Label.unique_label({:some_topic, :inserted}) == :ew_i_for_some_topic
  end

  test "ecto schema + update_type" do
    assert Label.unique_label({Thing, :updated}) == :ew_u_for_ectowatch_labeltest_thing
    assert Label.unique_label({Thing, :deleted}) == :ew_d_for_ectowatch_labeltest_thing
    assert Label.unique_label({Thing, :inserted}) == :ew_i_for_ectowatch_labeltest_thing
  end

  test "long atom + update_type" do
    assert Label.unique_label(
             {:super_long_super_long_super_long_super_long_super_long_super_long, :updated}
           ) == :ew_u_for_super_long_super_long_super_long_super_l_62135037

    assert Label.unique_label(
             {:super_long_super_long_super_long_super_long_super_long_super_long, :deleted}
           ) == :ew_d_for_super_long_super_long_super_long_super_l_62135037

    assert Label.unique_label(
             {:super_long_super_long_super_long_super_long_super_long_super_long, :inserted}
           ) == :ew_i_for_super_long_super_long_super_long_super_l_62135037
  end

  test "long atom with same prefix do not collide!" do
    assert Label.unique_label(
             {:super_long_super_long_super_long_super_long_super_long_super_long1, :updated}
           ) == :ew_u_for_super_long_super_long_super_long_super__117515674

    assert Label.unique_label(
             {:super_long_super_long_super_long_super_long_super_long_super_long2, :updated}
           ) == :ew_u_for_super_long_super_long_super_long_super_l_76543505
  end
end
