defmodule Jokers.ColorsTest do
  use ExUnit.Case, async: true

  alias Jokers.Colors

  test "getting colors" do
    colors4 = Colors.get(4)
    colors6 = Colors.get(6)
    assert colors4 == [:blue, :yellow, :black, :red]
    assert colors6 == [:green, :white, :blue, :yellow, :black, :red]
    assert Colors.get_next(colors4, :red, :right) == :blue
    assert Colors.get_next(colors4, :blue, :left) == :red
    assert Colors.get_next(colors6, :red, :right) == :green
    assert Colors.get_next(colors6, :green, :left) == :red
    assert Colors.get_next_teammate(colors4, :black, %{blue: %{0 => nil, 1 => :blue, 2 => :blue, 3 => :blue, 4 => :blue}}) == :blue
    assert Colors.get_next_teammate(colors6, :black, %{blue: %{0 => nil, 1 => :blue, 2 => :blue, 3 => :blue, 4 => :blue}}) == :blue
    assert Colors.get_next_teammate(colors6, :black, %{blue: %{0 => :blue, 1 => :blue, 2 => :blue, 3 => :blue, 4 => :blue}}) == :green
  end
end
