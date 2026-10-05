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

  @doc "CSS color for drawing a color's text, visible on a light background."
  def line_color(:white), do: "#a1a1aa"
  def line_color(color), do: marble_color(color)

  @doc """
  The board. `highlight` is a list of marbles to outline, such as the ones a previewed move changes.
  Clicking a marble in `clickable` sends a `"pick_marble"` event with the marble's color and index.
  `last_played` maps each color to the last card that player played, shown beside their side,
  and `names` maps each color to its player's name, written above that card.
  """
  attr :board, Board, required: true
  attr :viewer, :atom, default: nil, doc: "the color whose side is drawn at the bottom"
  attr :highlight, :list, default: []
  attr :clickable, :list, default: []
  attr :last_played, :map, default: %{}
  attr :names, :map, default: %{}

  attr :ghosts, :list,
    default: [],
    doc: "{marble, position} pairs: where marbles used to be, drawn as dashed outlines"

  def board(assigns) do
    geometry = geometry(assigns.board, assigns.viewer, assigns.names)

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
        stroke="#a8703c"
      />

      <text
        :for={{color, {x, y}, anchor} <- @geometry.labels}
        x={x}
        y={y}
        text-anchor={anchor}
        dominant-baseline="central"
        font-size={label_size()}
        font-weight="600"
        fill="#3f3f46"
      >
        <%= @names[color] %>
      </text>

      <g :for={{color, {x, y}} <- @geometry.piles}>
        <.svg_card card={@last_played[color]} x={x} y={y} />
      </g>

      <g :for={{{color, idx}, {x, y}} <- ghost_points(@board, @geometry, @ghosts)} class="ghost">
        <circle
          cx={x}
          cy={y}
          r={@geometry.hole * 1.15}
          fill="none"
          stroke={line_color(color)}
          stroke-width="2"
          stroke-dasharray="3 2"
        />
        <text
          x={x}
          y={y}
          text-anchor="middle"
          dominant-baseline="central"
          font-size="9"
          font-weight="bold"
          fill={if color == :yellow, do: "#18181b", else: line_color(color)}
        >
          <%= idx + 1 %>
        </text>
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
          r={@geometry.hole * 1.55}
          fill="none"
          stroke={emphasis_color(elem(marble, 0))}
          stroke-width="1.5"
          stroke-dasharray="3 2"
        />
        <circle
          cx={x}
          cy={y}
          r={@geometry.hole * 1.15}
          fill={marble_color(elem(marble, 0))}
          stroke={if marble in @highlight, do: emphasis_color(elem(marble, 0)), else: "#44403c"}
          stroke-width={if marble in @highlight, do: 3.5, else: 1}
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

  # marks for clickable and changed marbles: black, except white around black marbles
  defp emphasis_color(:black), do: "#fafafa"
  defp emphasis_color(_color), do: "#18181b"

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

  # house slots 1 to 5: two holes in from the home door, two along the side toward the barn,
  # then one more in, making a Z shape like the physical board (mirrored, to leave room at
  # the corner)
  @house_slots [
    {@home_door, 1},
    {@home_door, 2},
    {@home_door + 1, 2},
    {@home_door + 2, 2},
    {@home_door + 2, 3}
  ]

  # the barn is a diamond in from the barn door, with its 5 holes in a plus shape;
  # each hole is {along, in}, measured from the diamond's center in barn-hole spacings
  @barn_center {@barn_door, 2.5}
  @barn_hole_spacing 0.9
  @barn_holes [{0, -1}, {-1, 0}, {0, 0}, {1, 0}, {0, 1}]

  @label_size 15

  defp label_size, do: @label_size

  defp geometry(board, viewer, names) do
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

    # each player's last played card sits just outside the middle of their side; sides facing
    # down the screen leave a gap for the name, which goes between the card and the board
    piles =
      for color <- board.seats do
        {nx, ny} = inward(geometry, color)
        # how far the card reaches toward the board, for a card that isn't rotated
        reach = abs(nx) * @card_width / 2 + abs(ny) * @card_height / 2
        gap = 0.3 * @spacing + max(-ny, 0) * 1.1 * @spacing
        middle = track_point(geometry, color, @side_length / 2)
        {color, offset(middle, {nx, ny}, -(outline_margin + gap + reach))}
      end

    # each name sits above its player's card; on the left and right it starts at the card's
    # inner edge and runs outward, so a long name doesn't cover the board
    labels =
      for {color, {x, y}} <- piles, name = names[color] do
        {nx, _ny} = inward(geometry, color)
        width = String.length(name) * 0.62 * @label_size
        y = y - @card_height / 2 - 0.55 * @label_size

        cond do
          nx > 0.3 ->
            {color, {x + @card_width / 2, y}, "end", {x + @card_width / 2 - width, y}}

          nx < -0.3 ->
            {color, {x - @card_width / 2, y}, "start", {x - @card_width / 2 + width, y}}

          true ->
            {color, {x, y}, "middle", {x + width / 2, y}}
        end
      end

    # half the width of the drawing: enough for the board and the cards around it
    size =
      Enum.max(
        Enum.flat_map(vertices, fn {x, y} -> [abs(x) * outline_scale, abs(y) * outline_scale] end) ++
          Enum.flat_map(piles, fn {_color, {x, y}} ->
            [abs(x) + @card_width / 2, abs(y) + @card_height / 2]
          end) ++
          Enum.flat_map(labels, fn {_color, {_x, y}, _anchor, {far_x, _y}} ->
            [abs(far_x), abs(y) + @label_size / 2]
          end)
      ) + 0.3 * @spacing

    Map.merge(geometry, %{
      labels: Enum.map(labels, fn {color, point, anchor, _far} -> {color, point, anchor} end),
      piles: piles,
      view_box: "#{-size} #{-size} #{2 * size} #{2 * size}"
    })
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

  defp track_spots(board, geometry) do
    for color <- board.seats, p <- 0..(@side_length - 1) do
      {x, y} = track_point(geometry, color, p)
      %{x: x, y: y}
    end
  end

  defp marble_points(board, geometry) do
    for {color, positions} <- board.marbles,
        {position, idx} <- Enum.with_index(positions) do
      point =
        case position do
          :barn ->
            # barn marbles fill the barn holes in order, starting next to the track
            barn_idx = positions |> Enum.take(idx) |> Enum.count(&(&1 == :barn))
            barn_point(geometry, color, barn_idx)

          position ->
            position_point(board, geometry, color, position)
        end

      {{color, idx}, point}
    end
  end

  # ghosts in the barn aren't drawn: which barn hole a marble used is of no interest
  defp ghost_points(board, geometry, ghosts) do
    for {{color, _idx} = marble, position} <- ghosts,
        position != :barn,
        do: {marble, position_point(board, geometry, color, position)}
  end

  defp position_point(board, geometry, _color, {:track, _} = position) do
    {side, p} = Board.side_position(board, position)
    track_point(geometry, side, p)
  end

  defp position_point(_board, geometry, color, {:house, slot}),
    do: house_point(geometry, color, slot)

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
          do: "border-zinc-900 -translate-y-2",
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

  @doc """
  What a player's last move (see `Jokers.Game`) did, one part per marble it moved: the
  marble, the step that moved it (nil when a 5th discard in a row brought it out), where it
  started and ended, and the marbles it hit, with where they went.
  """
  def last_move_parts(%{steps: nil, before: before, after: after_move}) do
    for marble <- changed_marbles(before, after_move) do
      %{marble: marble, step: nil, from: :barn, to: Board.position(after_move, marble), hits: []}
    end
  end

  def last_move_parts(%{steps: steps, before: before}) do
    # replayed one step at a time, so each part starts where the previous one left the board
    {parts, _board} =
      Enum.map_reduce(steps, before, fn step, board ->
        {:ok, next} = Board.apply_step(board, step)
        changed = changed_marbles(board, next)
        marble = step_marble(step, board, changed)

        part = %{
          marble: marble,
          step: step,
          from: Board.position(board, marble),
          to: Board.position(next, marble),
          hits: for(hit <- changed -- [marble], do: {hit, Board.position(next, hit)})
        }

        {part, next}
      end)

    parts
  end

  # a marble coming out of the barn is the one of its color that left the barn
  defp step_marble({:come_out, color}, board, changed), do: came_out(color, board, changed)

  defp step_marble({:joker_teammate, color, _teammate}, board, changed),
    do: came_out(color, board, changed)

  defp step_marble({_direction_or_joker, marble, _n_or_target}, _board, _changed), do: marble

  defp came_out(color, board, changed) do
    Enum.find(changed, &(match?({^color, _}, &1) and Board.position(board, &1) == :barn))
  end

  @doc "Describes a player's last move in words, for that player."
  def describe_last_move(%{steps: steps, before: board} = last_move) do
    parts = last_move_parts(last_move)

    case {steps, parts} do
      {nil, []} ->
        "You discarded."

      {nil, [%{marble: marble, to: to}]} ->
        "You discarded, and as it was your 5th discard in a row, " <>
          "#{marble_name(marble)} came out onto #{place(board, marble, to)}."

      {_steps, parts} ->
        Enum.map_join(parts, " ", &describe_part(board, &1))
    end
  end

  defp describe_part(board, %{marble: marble, from: from, to: to, step: step} = part) do
    name = marble_name(marble)

    moved =
      case step do
        {direction, _marble, n} when direction in [:forward, :backward] ->
          word = if direction == :forward, do: "forward", else: "back"

          "#{name} moved #{n} #{word}, from #{place(board, marble, from)} to #{place(board, marble, to)}."

        {:joker, _marble, _target} ->
          "#{name} jumped from #{place(board, marble, from)} to #{place(board, marble, to)}."

        _come_out ->
          "#{name} came out onto #{place(board, marble, to)}."
      end

    hits =
      for {hit, position} <- part.hits do
        where = if position == :barn, do: "back to the barn", else: "to its home door"
        " It hit #{marble_name(hit)}, which went #{where}."
      end

    moved <> Enum.join(hits)
  end

  # a position in words a player can find on the board: track positions are counted from
  # the nearest barn or home door
  defp place(_board, {color, _idx}, {:house, slot}), do: "#{color}'s house slot #{slot}"
  defp place(_board, {color, _idx}, :barn), do: "#{color}'s barn"

  defp place(board, _marble, {:track, index} = position) do
    {side, p} = Board.side_position(board, position)

    cond do
      p == @barn_door ->
        "#{side}'s barn door"

      p == @home_door ->
        "#{side}'s home door"

      p < @home_door ->
        spots(@home_door - p, "before", "#{side}'s home door")

      p <= 5 ->
        spots(p - @home_door, "past", "#{side}'s home door")

      p < @barn_door ->
        spots(@barn_door - p, "before", "#{side}'s barn door")

      p <= 14 ->
        spots(p - @barn_door, "past", "#{side}'s barn door")

      true ->
        # closer to the next side's home door
        distance = @side_length + @home_door - p
        index = rem(index + distance, Board.track_length(board))
        {next_side, _home_door} = Board.side_position(board, {:track, index})
        spots(distance, "before", "#{next_side}'s home door")
    end
  end

  defp spots(1, word, door), do: "1 spot #{word} #{door}"
  defp spots(n, word, door), do: "#{n} spots #{word} #{door}"

  @doc "The marbles whose position differs between two boards."
  def changed_marbles(before, after_move) do
    for {color, positions} <- before.marbles,
        {{old, new}, idx} <- Enum.with_index(Enum.zip(positions, after_move.marbles[color])),
        old != new,
        do: {color, idx}
  end
end
