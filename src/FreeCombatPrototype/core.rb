# RGSS3 / Ruby 1.9 compatible; coordinates and speeds are in pixels.
module FreeCombatPrototype
  Body = Struct.new(:x, :y, :radius, :hp, :facing_x, :facing_y, :cooldown)

  class World
    WIDTH = 544
    HEIGHT = 416
    # shortcut: 16-pixel routing suits this arena; refine for narrow custom maps.
    NAV_STEP = 16
    attr_reader :player, :enemy, :walls

    def initialize
      @walls = []
      @player = Body.new(0.0, 0.0, 10.0, 100, 1.0, 0.0, 0)
      @enemy = Body.new(0.0, 0.0, 11.0, 100, -1.0, 0.0, 0)
    end

    def alive?(body)
      body.hp > 0
    end

    def collision_walls(x1, y1, x2, y2, radius)
      @walls
    end

    def blocked?(x, y, radius)
      collision_walls(x, y, x, y, radius).any? do |wx, wy, width, height|
        cx = [[x, wx].max, wx + width].min
        cy = [[y, wy].max, wy + height].min
        (x - cx) ** 2 + (y - cy) ** 2 < radius ** 2 ||
          (x >= wx && x <= wx + width && y >= wy && y <= wy + height)
      end
    end

    def occupied?(body, x, y)
      other = body.equal?(@player) ? @enemy : @player
      blocked?(x, y, body.radius) ||
        (alive?(other) && (x - other.x) ** 2 + (y - other.y) ** 2 <
          (body.radius + other.radius) ** 2)
    end

    def move(body, dx, dy)
      # Substeps prevent fast bodies and diagonal movement from crossing walls.
      steps = [(Math.sqrt(dx * dx + dy * dy) / 2.0).ceil, 1].max
      steps.times do
        nx = body.x + dx / steps
        body.x = nx unless occupied?(body, nx, body.y)
        ny = body.y + dy / steps
        body.y = ny unless occupied?(body, body.x, ny)
      end
    end

    def segment_hits_rect?(x1, y1, x2, y2, left, top, width, height, open_edges = false)
      first, last = 0.0, 1.0
      [[x1, x2 - x1, left, left + width], [y1, y2 - y1, top, top + height]].each do |origin, delta, low, high|
        if delta == 0
          inside = open_edges ? origin > low && origin < high : origin >= low && origin <= high
          return false unless inside
        else
          near, far = [(low - origin).to_f / delta, (high - origin).to_f / delta].minmax
          first = [first, near].max
          last = [last, far].min
          return false if open_edges ? first >= last : first > last
        end
      end
      true
    end

    def clear_line?(x1, y1, x2, y2, radius = 0)
      dx, dy = x2 - x1, y2 - y1
      length_squared = dx * dx + dy * dy
      collision_walls(x1, y1, x2, y2, radius).none? do |wx, wy, width, height|
        if radius == 0
          segment_hits_rect?(x1, y1, x2, y2, wx, wy, width, height)
        else
          # A rectangle swept by a circle is two rectangles plus four round corners.
          segment_hits_rect?(x1, y1, x2, y2, wx - radius, wy, width + radius * 2, height, true) ||
            segment_hits_rect?(x1, y1, x2, y2, wx, wy - radius, width, height + radius * 2, true) ||
            [[wx, wy], [wx + width, wy], [wx, wy + height], [wx + width, wy + height]].any? do |cx, cy|
              t = length_squared == 0 ? 0 : [[((cx - x1) * dx + (cy - y1) * dy).to_f / length_squared, 0].max, 1].min
              (x1 + dx * t - cx) ** 2 + (y1 + dy * t - cy) ** 2 < radius ** 2
            end
        end
      end
    end

    def navigation_bounds
      [0, 0, WIDTH, HEIGHT]
    end

    def navigation_open?(point, radius)
      @navigation_cells ||= {}
      return @navigation_cells[point] if @navigation_cells.has_key?(point)
      left, top, right, bottom = navigation_bounds
      x, y = point
      @navigation_cells[point] = x.between?(left + radius, right - radius) &&
        y.between?(top + radius, bottom - radius) && !blocked?(x, y, radius)
    end

    def path_checkpoint
    end

    def route_push(heap, entry)
      index = heap.size
      heap << entry
      while index > 0
        parent = (index - 1) / 2
        break if heap[parent][0] <= entry[0]
        heap[index] = heap[parent]
        index = parent
      end
      heap[index] = entry
    end

    def route_pop(heap)
      first, last = heap.first, heap.pop
      unless heap.empty?
        index = 0
        while index * 2 + 1 < heap.size
          child = index * 2 + 1
          child += 1 if child + 1 < heap.size && heap[child + 1][0] < heap[child][0]
          break if last[0] <= heap[child][0]
          heap[index] = heap[child]
          index = child
        end
        heap[index] = last
      end
      first
    end

    def find_enemy_path
      radius = @enemy.radius
      cx = (@enemy.x / NAV_STEP).round * NAV_STEP
      cy = (@enemy.y / NAV_STEP).round * NAV_STEP
      queue = []
      parents = {}
      costs = {}
      [-NAV_STEP, 0, NAV_STEP].each do |dx|
        [-NAV_STEP, 0, NAV_STEP].each do |dy|
          point = [cx + dx, cy + dy]
          next unless navigation_open?(point, radius) && clear_line?(@enemy.x, @enemy.y, point[0], point[1], radius)
          costs[point] = 0
          route_push(queue, [(point[0]-@player.x).abs+(point[1]-@player.y).abs, 0, point])
          parents[point] = nil
        end
      end
      goal = nil
      until queue.empty?
        path_checkpoint
        priority, cost, point = route_pop(queue)
        next if cost != costs[point]
        if (point[0] - @player.x) ** 2 + (point[1] - @player.y) ** 2 <= 28 ** 2 &&
            clear_line?(point[0], point[1], @player.x, @player.y)
          goal = point
          break
        end
        [[NAV_STEP, 0], [-NAV_STEP, 0], [0, NAV_STEP], [0, -NAV_STEP]].each do |dx, dy|
          neighbor = [point[0] + dx, point[1] + dy]
          next if costs.has_key?(neighbor) && costs[neighbor] <= cost + NAV_STEP
          next unless navigation_open?(neighbor, radius)
          next unless clear_line?(point[0], point[1], neighbor[0], neighbor[1], radius)
          parents[neighbor] = point
          costs[neighbor] = cost + NAV_STEP
          priority = costs[neighbor] + (neighbor[0]-@player.x).abs + (neighbor[1]-@player.y).abs
          route_push(queue, [priority, costs[neighbor], neighbor])
        end
      end
      return [] unless goal
      points = []
      while goal
        points.unshift(goal)
        goal = parents[goal]
      end
      route = []
      x, y = @enemy.x, @enemy.y
      until points.empty?
        path_checkpoint
        last = points.size - 1
        while last > 0 && !clear_line?(x, y, points[last][0], points[last][1], radius)
          path_checkpoint
          last -= 1
        end
        point = points[last]
        route << point
        x, y = point
        points = points.drop(last + 1)
      end
      route
    end

    def enemy_destination
      if clear_line?(@enemy.x, @enemy.y, @player.x, @player.y, @enemy.radius)
        @enemy_path = nil
        return [@player.x, @player.y]
      end
      @path_timer = (@path_timer || 0) - 1
      target = [@player.x, @player.y]
      if @enemy_path.nil? || (@path_timer <= 0 && @path_target != target)
        @enemy_path = find_enemy_path
        @path_target = target
        @path_timer = 20
      end
      while @enemy_path.first && (@enemy_path[0][0] - @enemy.x).abs < 0.01 && (@enemy_path[0][1] - @enemy.y).abs < 0.01
        @enemy_path.shift
      end
      @enemy_path.first
    end

  end
end
