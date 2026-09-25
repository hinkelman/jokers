defmodule JokersWeb.BoardComponents do
  @moduledoc """
  Draws the board as an SVG, plus cards and descriptions of moves.

  The board is a regular polygon with one side per seat. It is rotated so the viewer's side
  is at the bottom, with position 0 at the bottom-right corner; positions count up clockwise,
  the direction marbles move forward.
  """

  use Phoenix.Component

  alias Jokers.Board
  alias JokersWeb.MovePicker

  # distance between neighboring holes, in SVG units
  @spacing 20
  @side_length 18
  @barn_door 8
  @home_door 3

  @marble_colors %{
    red: "#dc2626",
    black: "#27272a",
    yellow: "#facc15",
    blue: "#2563eb",
    green: "#16a34a",
    white: "#f8fafc"
  }

  @doc "CSS color for a marble color."
  def marble_color(color), do: Map.fetch!(@marble_colors, color)

  @doc "CSS color for drawing a color's rings and text, visible on a light background."
  def line_color(:white), do: "#a1a1aa"
  def line_color(color), do: marble_color(color)

  @doc """
  The board. `highlight` is a list of marbles to ring, such as the ones a previewed move changes.
  Clicking a marble in `clickable` sends a `"pick_marble"` event with the marble's color and index.
  """
  attr :board, Board, required: true
  attr :viewer, :atom, default: nil, doc: "the color whose side is drawn at the bottom"
  attr :highlight, :list, default: []
  attr :clickable, :list, default: []

  def board(assigns) do
    geometry = geometry(assigns.board, assigns.viewer)
    assigns = assign(assigns, geometry: geometry, spots: spots(assigns.board, geometry))

    ~H"""
    <svg
      viewBox={@geometry.view_box}
      class="w-full h-auto select-none"
      role="img"
      aria-label="Game board"
    >
      <polygon points={@geometry.outline} fill="#e7e5e4" stroke="#a8a29e" stroke-width="2" />
      <text
        :for={{color, {x, y}} <- @geometry.labels}
        x={x}
        y={y}
        text-anchor="middle"
        dominant-baseline="middle"
        font-size="16"
        fill="#57534e"
      >
        <%= color %>
      </text>
      <circle
        :for={spot <- @spots}
        cx={spot.x}
        cy={spot.y}
        r={@geometry.hole}
        fill="#fafaf9"
        stroke={spot.ring || "#d6d3d1"}
        stroke-width={if spot.ring, do: 3, else: 1}
      />
      <g
        :for={{marble, {x, y}} <- marble_points(@board, @geometry)}
        phx-click={if marble in @clickable, do: "pick_marble"}
        phx-value-color={elem(marble, 0)}
        phx-value-index={elem(marble, 1)}
        style={if marble in @clickable, do: "cursor: pointer"}
      >
        <circle
          :if={marble in @clickable}
          cx={x}
          cy={y}
          r={@geometry.hole * 1.5}
          fill="#fed7aa"
          stroke="#f97316"
          stroke-width="1.5"
          stroke-dasharray="3 2"
        />
        <circle
          cx={x}
          cy={y}
          r={@geometry.hole * 1.15}
          fill={marble_color(elem(marble, 0))}
          stroke={if marble in @highlight, do: "#f97316", else: "#44403c"}
          stroke-width={if marble in @highlight, do: 4, else: 1}
        />
        <text
          x={x}
          y={y}
          text-anchor="middle"
          dominant-baseline="central"
          font-size="9"
          font-weight="bold"
          fill={if elem(marble, 0) in [:yellow, :white], do: "#18181b", else: "#fafafa"}
        >
          <%= elem(marble, 1) + 1 %>
        </text>
      </g>
    </svg>
    """
  end

  ## Geometry

  defp geometry(board, viewer) do
    n = length(board.seats)
    side = @side_length * @spacing
    radius = side / (2 * :math.sin(:math.pi() / n))
    viewer_seat = Enum.find_index(board.seats, &(&1 == viewer)) || 0

    # drawn side k (counting clockwise from the bottom) runs from vertex k to vertex k + 1
    vertices =
      for i <- 0..n do
        angle = :math.pi() / 2 - :math.pi() / n + i * 2 * :math.pi() / n
        {radius * :math.cos(angle), radius * :math.sin(angle)}
      end

    # half the width of the drawing, leaving room for the side labels
    size =
      (vertices |> Enum.flat_map(fn {x, y} -> [abs(x), abs(y)] end) |> Enum.max()) +
        4 * @spacing

    # which drawn side each color's seat is on
    drawn_sides =
      board.seats
      |> Enum.with_index()
      |> Map.new(fn {color, seat} -> {color, rem(seat - viewer_seat + n, n)} end)

    # the outline sits one hole-spacing outside the track
    apothem = radius * :math.cos(:math.pi() / n)
    outline_scale = (apothem + @spacing) / apothem

    geometry = %{
      drawn_sides: drawn_sides,
      vertices: List.to_tuple(vertices),
      hole: @spacing * 0.32,
      view_box: "#{-size} #{-size} #{2 * size} #{2 * size}",
      outline:
        Enum.map_join(vertices, " ", fn {x, y} -> "#{x * outline_scale},#{y * outline_scale}" end)
    }

    # each side's color name, just outside the middle of the side
    labels =
      for color <- board.seats do
        middle = track_point(geometry, color, (@side_length - 1) / 2)
        {color, offset(middle, inward(geometry, color), -2.8 * @spacing)}
      end

    Map.put(geometry, :labels, labels)
  end

  # a point along a color's side; p may be fractional
  defp track_point(geometry, color, p) do
    k = geometry.drawn_sides[color]
    {x1, y1} = elem(geometry.vertices, k)
    {x2, y2} = elem(geometry.vertices, k + 1)
    t = (p + 0.5) / @side_length
    {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t}
  end

  # unit vector from a color's side toward the center of the board
  defp inward(geometry, color) do
    {x, y} = track_point(geometry, color, (@side_length - 1) / 2)
    length = :math.sqrt(x * x + y * y)
    {-x / length, -y / length}
  end

  defp offset({x, y}, {dx, dy}, distance), do: {x + dx * distance, y + dy * distance}

  defp house_point(geometry, color, slot) do
    offset(track_point(geometry, color, @home_door), inward(geometry, color), slot * @spacing)
  end

  defp barn_point(geometry, color, i) do
    offset(
      track_point(geometry, color, @barn_door - 2 + i),
      inward(geometry, color),
      2.5 * @spacing
    )
  end

  # every hole on the board: the track, the houses and the barns;
  # the barn and home doors are ringed in the side's color
  defp spots(board, geometry) do
    Enum.flat_map(board.seats, fn color ->
      track =
        for p <- 0..(@side_length - 1) do
          ring = if p in [@barn_door, @home_door], do: line_color(color)
          {track_point(geometry, color, p), ring}
        end

      house = for slot <- 1..5, do: {house_point(geometry, color, slot), nil}
      barn = for i <- 0..4, do: {barn_point(geometry, color, i), nil}

      for {{x, y}, ring} <- track ++ house ++ barn, do: %{x: x, y: y, ring: ring}
    end)
  end

  defp marble_points(board, geometry) do
    for {color, positions} <- board.marbles,
        {position, idx} <- Enum.with_index(positions) do
      point =
        case position do
          {:track, _} = track ->
            {side, p} = Board.side_position(board, track)
            track_point(geometry, side, p)

          {:house, slot} ->
            house_point(geometry, color, slot)

          :barn ->
            # barn marbles fill the barn spots in order
            barn_idx = positions |> Enum.take(idx) |> Enum.count(&(&1 == :barn))
            barn_point(geometry, color, barn_idx)
        end

      {{color, idx}, point}
    end
  end

  ## Cards and moves

  @suits %{hearts: "♥", diamonds: "♦", clubs: "♣", spades: "♠"}

  @doc "A playing card, drawn as a button."
  attr :card, :any, required: true
  attr :selected, :boolean, default: false
  attr :rest, :global

  def card(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex h-20 w-14 flex-col items-center justify-center rounded-lg border-2 bg-white text-xl font-bold shadow-sm",
        card_text_color(@card),
        if(@selected,
          do: "border-orange-500 -translate-y-2",
          else: "border-zinc-300 hover:border-zinc-500"
        )
      ]}
      {@rest}
    >
      <span><%= card_rank(@card) %></span>
      <span :if={elem(@card, 1) != :joker}><%= suit_symbol(@card) %></span>
    </button>
    """
  end

  defp suit_symbol({suit, _rank}), do: @suits[suit]

  defp card_rank({_color, :joker}), do: "🃏"
  defp card_rank({_suit, rank}) when is_integer(rank), do: Integer.to_string(rank)
  defp card_rank({_suit, rank}), do: rank |> Atom.to_string() |> String.first() |> String.upcase()

  defp card_text_color({suit, _}) when suit in [:hearts, :diamonds, :red], do: "text-red-600"
  defp card_text_color(_card), do: "text-zinc-900"

  @doc "A short name for a card, like \"Q♥\"."
  def card_name({_color, :joker} = card), do: card_rank(card)
  def card_name(card), do: card_rank(card) <> suit_symbol(card)

  @doc "Describes a move (a list of steps) in words."
  def describe_move(board, steps), do: Enum.map_join(steps, ", then ", &describe_step(board, &1))

  defp describe_step(_board, {direction, marble, n}) when direction in [:forward, :backward] do
    word = if direction == :forward, do: "forward", else: "back"
    "#{marble_name(marble)} #{word} #{n}"
  end

  defp describe_step(_board, {:come_out, color}), do: "bring a #{color} marble out"

  defp describe_step(board, {:joker, marble, target}) do
    "#{marble_name(marble)} jumps onto #{marble_name(MovePicker.marble_at(board, target))}"
  end

  defp describe_step(_board, {:joker_teammate, color, teammate}) do
    "bring a #{color} marble out onto #{teammate}'s barn door"
  end

  defp marble_name({color, idx}), do: "#{color} #{idx + 1}"
end
