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
  `last_played` maps each color to the last card that player played, shown beside their side.
  """
  attr :board, Board, required: true
  attr :viewer, :atom, default: nil, doc: "the color whose side is drawn at the bottom"
  attr :highlight, :list, default: []
  attr :clickable, :list, default: []
  attr :last_played, :map, default: %{}

  def board(assigns) do
    geometry = geometry(assigns.board, assigns.viewer)

    assigns =
      assign(assigns,
        geometry: geometry,
        track: track_spots(assigns.board, geometry),
        shapes: Enum.map(assigns.board.seats, &shape(geometry, &1))
      )

    # flattened for rendering: every barn and house polygon, and every hole in them
    assigns =
      assign(assigns,
        polygons:
          for(shape <- assigns.shapes, points <- shape.polygons, do: {shape.color, points}),
        shape_holes: for(shape <- assigns.shapes, hole <- shape.holes, do: {shape.color, hole})
      )

    ~H"""
    <svg
      viewBox={@geometry.view_box}
      class="w-full h-auto select-none"
      role="img"
      aria-label="Game board"
    >
      <polygon points={@geometry.outline} fill="#d4935a" stroke="#9a5f2c" stroke-width="2" />

      <%!-- barns and houses: outlines first, then fills on top, so only the outer edge shows --%>
      <polygon
        :for={{_color, points} <- @polygons}
        points={points}
        fill="#18181b"
        stroke="#18181b"
        stroke-width="3"
      />
      <polygon :for={{color, points} <- @polygons} points={points} fill={marble_color(color)} />
      <circle
        :for={{color, {x, y}} <- @shape_holes}
        cx={x}
        cy={y}
        r={@geometry.hole}
        fill={shape_hole_color(color)}
      />

      <circle
        :for={spot <- @track}
        cx={spot.x}
        cy={spot.y}
        r={@geometry.hole}
        fill="#ecd3ac"
        stroke={spot.ring || "#a8703c"}
        stroke-width={if spot.ring, do: 3, else: 1}
      />

      <g :for={{color, {x, y}} <- @geometry.piles}>
        <.svg_card card={@last_played[color]} x={x} y={y} />
      </g>

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

  # holes in a barn or house are a darker shade of its color
  defp shape_hole_color(:black), do: "rgba(255, 255, 255, 0.25)"
  defp shape_hole_color(:white), do: "rgba(0, 0, 0, 0.18)"
  defp shape_hole_color(_color), do: "rgba(0, 0, 0, 0.3)"

  @card_width 34
  @card_height 48

  attr :card, :any, required: true
  attr :x, :float, required: true
  attr :y, :float, required: true

  defp svg_card(%{card: nil} = assigns) do
    ~H"""
    <rect
      x={@x - card_width() / 2}
      y={@y - card_height() / 2}
      width={card_width()}
      height={card_height()}
      rx="4"
      fill="none"
      stroke="#d6d3d1"
      stroke-dasharray="4 3"
    />
    """
  end

  defp svg_card(assigns) do
    ~H"""
    <rect
      x={@x - card_width() / 2}
      y={@y - card_height() / 2}
      width={card_width()}
      height={card_height()}
      rx="4"
      fill="#ffffff"
      stroke="#a1a1aa"
    />
    <g
      fill={if red_card?(@card), do: "#dc2626", else: "#18181b"}
      text-anchor="middle"
      font-weight="bold"
    >
      <%= if joker?(@card) do %>
        <text x={@x} y={@y - 4} font-size="22" dominant-baseline="central">★</text>
        <text x={@x} y={@y + 15} font-size="7" dominant-baseline="central">JOKER</text>
      <% else %>
        <text x={@x} y={@y - 9} font-size="16" dominant-baseline="central">
          <%= card_rank(@card) %>
        </text>
        <text x={@x} y={@y + 10} font-size="16" dominant-baseline="central">
          <%= suit_symbol(@card) %>
        </text>
      <% end %>
    </g>
    """
  end

  defp card_width, do: @card_width
  defp card_height, do: @card_height

  ## Geometry
  #
  # Each side has 18 evenly spaced holes, with position 0 on the side's right-hand corner, so
  # the track runs through every corner of the board. Barns and houses are placed in each
  # side's own coordinates: a distance along the side (in positions) and a distance in from
  # the track toward the center (in hole spacings).

  # house slots 1 to 5: two holes in from the home door, two along the side toward the corner,
  # then one more in, making a Z shape like the physical board
  @house_slots [
    {@home_door, 1},
    {@home_door, 2},
    {@home_door - 1, 2},
    {@home_door - 2, 2},
    {@home_door - 2, 3}
  ]

  # the barn is a diamond in from the barn door, with its 5 holes in a plus shape;
  # each hole is {along, in}, measured from the diamond's center in barn-hole spacings
  @barn_center {@barn_door, 2.9}
  @barn_hole_spacing 0.9
  @barn_holes [{0, -1}, {-1, 0}, {0, 0}, {1, 0}, {0, 1}]

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

    # which drawn side each color's seat is on
    drawn_sides =
      board.seats
      |> Enum.with_index()
      |> Map.new(fn {color, seat} -> {color, rem(seat - viewer_seat + n, n)} end)

    # the outline sits a little more than one hole-spacing outside the track
    apothem = radius * :math.cos(:math.pi() / n)
    outline_margin = 1.2 * @spacing
    outline_scale = (apothem + outline_margin) / apothem

    geometry = %{
      drawn_sides: drawn_sides,
      vertices: List.to_tuple(vertices),
      hole: @spacing * 0.32,
      outline:
        Enum.map_join(vertices, " ", fn {x, y} -> "#{x * outline_scale},#{y * outline_scale}" end)
    }

    # each player's last played card sits just outside the middle of their side
    piles =
      for color <- board.seats do
        {nx, ny} = inward(geometry, color)
        # how far the card reaches toward the board, for a card that isn't rotated
        reach = abs(nx) * @card_width / 2 + abs(ny) * @card_height / 2
        middle = track_point(geometry, color, @side_length / 2)
        {color, offset(middle, {nx, ny}, -(outline_margin + 0.3 * @spacing + reach))}
      end

    # half the width of the drawing: enough for the board and the cards around it
    size =
      Enum.max(
        Enum.flat_map(vertices, fn {x, y} -> [abs(x) * outline_scale, abs(y) * outline_scale] end) ++
          Enum.flat_map(piles, fn {_color, {x, y}} ->
            [abs(x) + @card_width / 2, abs(y) + @card_height / 2]
          end)
      ) + 0.3 * @spacing

    Map.merge(geometry, %{piles: piles, view_box: "#{-size} #{-size} #{2 * size} #{2 * size}"})
  end

  # a point along a color's side; p may be fractional, and position 0 is on the corner
  defp track_point(geometry, color, p) do
    k = geometry.drawn_sides[color]
    {x1, y1} = elem(geometry.vertices, k)
    {x2, y2} = elem(geometry.vertices, k + 1)
    t = p / @side_length
    {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t}
  end

  # a point in a side's own coordinates: `along` in positions, `in_` in hole spacings
  defp local_point(geometry, color, along, in_) do
    offset(track_point(geometry, color, along), inward(geometry, color), in_ * @spacing)
  end

  # unit vector from a color's side toward the center of the board
  defp inward(geometry, color) do
    {x, y} = track_point(geometry, color, @side_length / 2)
    length = :math.sqrt(x * x + y * y)
    {-x / length, -y / length}
  end

  # unit vector along a color's side, in the forward direction
  defp along(geometry, color) do
    k = geometry.drawn_sides[color]
    {x1, y1} = elem(geometry.vertices, k)
    {x2, y2} = elem(geometry.vertices, k + 1)
    length = :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
    {(x2 - x1) / length, (y2 - y1) / length}
  end

  defp offset({x, y}, {dx, dy}, distance), do: {x + dx * distance, y + dy * distance}

  defp house_point(geometry, color, slot) do
    {along, in_} = Enum.at(@house_slots, slot - 1)
    local_point(geometry, color, along, in_)
  end

  defp barn_point(geometry, color, i) do
    {center_along, center_in} = @barn_center
    {da, di} = Enum.at(@barn_holes, i)

    local_point(
      geometry,
      color,
      center_along + da * @barn_hole_spacing,
      center_in + di * @barn_hole_spacing
    )
  end

  # the colored barn diamond and house cells for one color, with their holes
  defp shape(geometry, color) do
    a = along(geometry, color)
    i = inward(geometry, color)
    {center_along, center_in} = @barn_center
    barn_center = local_point(geometry, color, center_along, center_in)
    barn_radius = (@barn_hole_spacing + 0.75) * @spacing
    # house cells overlap slightly so they join into one shape
    cell = 0.54 * @spacing

    barn = [
      offset(barn_center, a, barn_radius),
      offset(barn_center, i, barn_radius),
      offset(barn_center, a, -barn_radius),
      offset(barn_center, i, -barn_radius)
    ]

    cells =
      for slot <- 1..5 do
        center = house_point(geometry, color, slot)

        for {sa, si} <- [{1, 1}, {1, -1}, {-1, -1}, {-1, 1}] do
          center |> offset(a, sa * cell) |> offset(i, si * cell)
        end
      end

    %{
      color: color,
      polygons: Enum.map([barn | cells], &points/1),
      holes:
        for(slot <- 1..5, do: house_point(geometry, color, slot)) ++
          for(hole <- 0..4, do: barn_point(geometry, color, hole))
    }
  end

  defp points(corners), do: Enum.map_join(corners, " ", fn {x, y} -> "#{x},#{y}" end)

  # the track holes; the barn and home doors are ringed in the side's color
  defp track_spots(board, geometry) do
    for color <- board.seats, p <- 0..(@side_length - 1) do
      {x, y} = track_point(geometry, color, p)
      %{x: x, y: y, ring: if(p in [@barn_door, @home_door], do: line_color(color))}
    end
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
            # barn marbles fill the barn holes in order, starting next to the track
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
        if(red_card?(@card), do: "text-red-600", else: "text-zinc-900"),
        if(@selected,
          do: "border-orange-500 -translate-y-2",
          else: "border-zinc-300 hover:border-zinc-500"
        )
      ]}
      {@rest}
    >
      <%= if joker?(@card) do %>
        <span class="text-3xl leading-none">★</span>
        <span class="mt-1 text-[10px] tracking-wider">JOKER</span>
      <% else %>
        <span><%= card_rank(@card) %></span>
        <span><%= suit_symbol(@card) %></span>
      <% end %>
    </button>
    """
  end

  defp joker?({_color, rank}), do: rank == :joker
  defp red_card?({suit, _rank}), do: suit in [:hearts, :diamonds, :red]

  defp suit_symbol({suit, _rank}), do: @suits[suit]

  defp card_rank({_suit, rank}) when is_integer(rank), do: Integer.to_string(rank)
  defp card_rank({_suit, rank}), do: rank |> Atom.to_string() |> String.first() |> String.upcase()

  @doc "A short name for a card, like \"Q♥\"."
  def card_name({_color, :joker}), do: "Joker"
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
