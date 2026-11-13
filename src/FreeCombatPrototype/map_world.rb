module FreeCombatPrototype
  class MapGeometry
    DIRECTIONS = [[2, 0, 1], [4, -1, 0], [6, 1, 0], [8, 0, -1]]
    attr_reader :bounds, :walls, :cells

    def initialize(map, start_x, start_y)
      @map = map
      @masks = {}
      @cells = [[start_x, start_y]]
      visited = { @cells.first => true }
      index = 0
      while index < @cells.size
        x, y = @cells[index]
        index += 1
        DIRECTIONS.each_with_index do |(direction, dx, dy), bit|
          nx, ny = x + dx, y + dy
          next unless @map.valid?(nx, ny) && mask(x, y) & (1 << bit) != 0
          next unless mask(nx, ny) & (1 << (3 - bit)) != 0
          point = [nx, ny]
          next if visited[point]
          visited[point] = true
          @cells << point
        end
      end
      @reachable = visited
      xs, ys = @cells.map { |c| c[0] }, @cells.map { |c| c[1] }
      left, top = [xs.min - 1, 0].max, [ys.min - 1, 0].max
      right, bottom = [xs.max + 2, @map.width].min, [ys.max + 2, @map.height].min
      @bounds = [left * 32, top * 32, right * 32, bottom * 32]
      @walls = []
      (top...bottom).each do |y|
        run = nil
        (left..right).each do |x|
          solid = x < right && mask(x, y) == 0
          run = x if solid && run.nil?
          if !solid && run
            @walls << [run * 32, y * 32, (x - run) * 32, 32]
            run = nil
          end
          next if x == right || solid
          m = mask(x, y)
          @walls << [x * 32, y * 32 + 31, 32, 1] if m & 1 == 0
          @walls << [x * 32, y * 32, 1, 32] if m & 2 == 0
          @walls << [x * 32 + 31, y * 32, 1, 32] if m & 4 == 0
          @walls << [x * 32, y * 32, 32, 1] if m & 8 == 0
        end
      end
    end

    def include?(x, y)
      @reachable.has_key?([x, y])
    end

    def mask(x, y)
      @masks[[x, y]] ||= DIRECTIONS.each_with_index.inject(0) do |value, ((direction, dx, dy), bit)|
        @map.valid?(x, y) && @map.passable?(x, y, direction) ? value | (1 << bit) : value
      end
    end
  end

  class MapWorld < World
    attr_reader :geometry
    attr_accessor :npc_bodies

    def initialize(map, player_x, player_y, enemy_x, enemy_y)
      super()
      @map = map
      @geometry = MapGeometry.new(map, (player_x / 32).floor, (player_y / 32).floor)
      @walls = @geometry.walls.dup
      @player.x, @player.y = player_x, player_y
      @enemy.x, @enemy.y = enemy_x, enemy_y
      @event_walls = []
    end

    def occupied?(body, x, y)
      return true if blocked?(x, y, body.radius)
      others = [body.equal?(@player) ? @enemy : @player] + (@npc_bodies ? @npc_bodies.values : [])
      others.any? do |other|
        next false if other.equal?(body) || !alive?(other)
        limit = (body.radius + other.radius) ** 2
        after = (x-other.x)**2 + (y-other.y)**2
        before = (body.x-other.x)**2 + (body.y-other.y)**2
        # Native wakeups/transfers may stack companions; permit only separation from existing overlap.
        after < limit && (before >= limit || after <= before)
      end
    end

    def route_clear?(body, x, y, target = nil)
      previous = @routing_bodies
      @routing_bodies = ((@npc_bodies || {}).values + [@player]).reject { |b| b.equal?(body) || b.equal?(target) || !alive?(b) }
      clear_line?(body.x, body.y, x, y, body.radius)
    ensure
      @routing_bodies = previous
    end

    # nil is pending; [] is a completed search with no path.
    def route_between(body, x, y, target = nil)
      @route_jobs ||= {}
      @route_queue ||= []
      id = body.object_id
      key = [(x / 16).floor, (y / 16).floor, @walls.object_id,
             (body.x / 16).floor, (body.y / 16).floor, body.radius]
      job = @route_jobs[id]
      unless job && job[0] == key
        blockers = ((@npc_bodies || {}).values + [@player]).reject { |b| b.equal?(body) || b.equal?(target) || !alive?(b) }.map { |b| b.dup }
        job = [key, Fiber.new { find_enemy_path }, {}, Body.new(x,y,0,1,0,1,0), body.dup, blockers]
        @route_jobs[id] = job
        @route_queue << id unless @route_queue.include?(id)
      end
      if @route_frame != Graphics.frame_count
        @route_frame, @route_seconds = Graphics.frame_count, 0.0
      end
      # Share the frame budget and rotate jobs so one unreachable target cannot stall the room.
      return nil if @route_seconds >= 0.004 || @route_queue.first != id
      saved = [@player, @enemy, @navigation_cells, @routing_bodies, @path_sliced]
      @player, @enemy, @navigation_cells, @routing_bodies = job[3], job[4], job[2], job[5]
      @path_sliced, @path_steps = true, 0
      started = Time.now
      @path_deadline = started + [0.001, 0.004 - @route_seconds].min
      result = job[1].resume
      if result.nil?
        @route_queue.rotate!
      else
        @route_jobs.delete(id)
        @route_queue.delete(id)
      end
      result
    ensure
      if saved
        @route_seconds += Time.now - started
        @player, @enemy, @navigation_cells, @routing_bodies, @path_sliced = saved
      end
    end

    def path_checkpoint
      return unless @path_sliced
      @path_steps += 1
      if @path_steps >= 32 || Time.now >= @path_deadline
        Fiber.yield(nil)
        @path_steps = 0
      end
    end

    def cancel_route(body)
      return unless @route_jobs
      @route_jobs.delete(body.object_id)
      @route_queue.delete(body.object_id)
    end

    def encounter_running?
      alive?(@player)
    end

    def navigation_bounds
      @geometry.bounds
    end

    def blocked?(x, y, radius)
      return super unless @geometry
      left, top, right, bottom = navigation_bounds
      x - radius < left || y - radius < top || x + radius > right || y + radius > bottom || super
    end

    def collision_walls(x1, y1, x2, y2, radius)
      # Event changes replace @walls and invalidate the tile index.
      unless @indexed_walls.equal?(@walls)
        @wall_buckets = Hash.new { |hash, key| hash[key] = [] }
        @walls.each do |wall|
          x, y, width, height = wall
          (x / 32..(x + width) / 32).each do |gx|
            (y / 32..(y + height) / 32).each { |gy| @wall_buckets[[gx, gy]] << wall }
          end
        end
        @indexed_walls = @walls
      end
      left, right = (([x1, x2].min - radius) / 32).floor, (([x1, x2].max + radius) / 32).floor
      top, bottom = (([y1, y2].min - radius) / 32).floor, (([y1, y2].max + radius) / 32).floor
      walls = []
      steps=[((x2-x1).abs/16.0).ceil,((y2-y1).abs/16.0).ceil,1].max
      padding=((radius+16)/32.0).ceil
      if (right-left+1)*(bottom-top+1)>[64,(steps+1)*(padding*2+1)**2].max
        # Long diagonal queries visit a thin corridor, not the entire enclosing room rectangle.
        visited={}
        (0..steps).each do |step|
          gx=((x1+(x2-x1)*step.to_f/steps)/32).floor
          gy=((y1+(y2-y1)*step.to_f/steps)/32).floor
          (gx-padding..gx+padding).each do |cx|
            (gy-padding..gy+padding).each do |cy|
              key=[cx,cy]
              next if visited[key]
              visited[key]=true
              bucket=@wall_buckets.fetch(key,nil)
              walls.concat(bucket) if bucket
            end
          end
        end
      else
        (left..right).each do |gx|
          (top..bottom).each do |gy|
            bucket = @wall_buckets.fetch([gx, gy],nil)
            walls.concat(bucket) if bucket
          end
        end
      end
      if @routing_bodies
        min_x,max_x=[x1,x2].min-radius,[x1,x2].max+radius
        min_y,max_y=[y1,y2].min-radius,[y1,y2].max+radius
        @routing_bodies.each do |body|
          next if body.x + body.radius < min_x || body.x-body.radius > max_x ||
            body.y+body.radius < min_y || body.y-body.radius > max_y
          walls << [body.x-body.radius,body.y-body.radius,body.radius*2,body.radius*2]
        end
      end
      walls.uniq.reject { |wall| @ignored_event_walls && @ignored_event_walls.include?(wall) }
    end

    # Targets remain solid to walking/pathfinding, but do not occlude their own hit tests.
    def without_event_walls(characters)
      previous = @ignored_event_walls
      @ignored_event_walls = characters.select { |event| event.respond_to?(:id) && @map.events[event.id].equal?(event) }.
        map { |event| [event.x * 32, event.y * 32, 32, 32] }
      yield
    ensure
      @ignored_event_walls = previous
    end

    def refresh_event_walls(events, opponent)
      left, top, right, bottom = navigation_bounds
      rectangles = events.select do |event|
        event && event != opponent && !event.erased && !event.deleted? && !event.through && event.normal_priority? &&
          (event.x * 32).between?(left, right - 1) && (event.y * 32).between?(top, bottom - 1)
      end.map { |event| [event.x * 32, event.y * 32, 32, 32] }
      return if rectangles == @event_walls
      @event_walls = rectangles
      @walls = @geometry.walls + rectangles
      @navigation_cells = @enemy_path = nil
    end
  end
end
