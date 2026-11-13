module FreeCombatPrototype
  class MapNPCs
    attr_reader :events
    def initialize(combat, world, opponent)
      @combat, @world = combat, world
      @events, @bodies, @orders, @routes = {}, {}, {}, {}
      @cells = {}
      @world.geometry.cells.each { |cell| @cells[cell] = true }
      @world.npc_bodies = @bodies
      if opponent
        opponent.actor.no_aggro = false
        register(opponent, world.enemy)
      end
    end

    def registered?(event)
      event && event.respond_to?(:id) && @events[event.id].equal?(event) && event.actor &&
        !event.erased && !event.deleted? && !event.actor.is_object && !event.actor.is_projectile && @cells.has_key?([event.x,event.y])
    end

    def body(event)
      @bodies[event.id] if registered?(event)
    end

    def target_body(event)
      event.equal?($game_player) ? @world.player : body(event)
    end

    def register(event, token = nil)
      return if registered?(event)
      # A returning native jump still renders at its airborne origin; continuous control cannot interpolate it.
      landing = event.respond_to?(:jumping?) && event.jumping? && event.actor.instance_variable_get(:@fcp_combat).equal?(@combat)
      if landing
        event.instance_variable_set(:@real_x, event.x)
        event.instance_variable_set(:@real_y, event.y)
        event.instance_variable_set(:@jump_count, 0)
      end
      @events[event.id] = event
      @bodies[event.id] = token || Body.new((event.real_x + 0.5) * 32, (event.real_y + 0.5) * 32, 11, event.actor.health, 0, 1, 0)
      attach_actor(event)
      @registry_dirty = true
    end

    def attach_actor(event)
      event.actor.extend(ContinuousSkills)
      event.actor.instance_variable_set(:@fcp_combat, @combat)
    end

    def spawn(name, x, y)
      points = @world.geometry.cells.sort_by { |cx,cy| (cx-x)**2+(cy-y)**2 }
      point = points.find do |cx,cy|
        px,py=cx*32+16,cy*32+16
        !@world.blocked?(px,py,11) && (@world.npc_bodies.values+[@world.player]).none? { |b| (b.x-px)**2+(b.y-py)**2 < 24**2 }
      end
      raise 'No free NPC test spawn' unless point
      event=$game_map.ask_summon_event(name,point[0],point[1])
      event.moveto(point[0],point[1])
      $game_map.add_event_to_pos_hash(event)
      register(event)
      event
    end

    def refresh
      map = $game_map
      @events.keys.each do |id|
        event = @events[id]
        next if map.events[id].equal?(event) && !event.deleted? && !event.erased && event.actor && !event.actor.is_object && !event.actor.is_projectile && @cells.has_key?([event.x,event.y])
        @world.cancel_route(@bodies[id])
        @events.delete(id); @bodies.delete(id); @orders.delete(id); @routes.delete(id)
      end
      map.events.values.each do |event|
        next if registered?(event) || !event.actor || event.actor.is_object || event.actor.is_projectile || event.deleted? || event.erased
        cell = [event.x, event.y]
        next unless @cells.has_key?(cell)
        register(event)
      end
      if @registry_dirty
        $game_map.refresh_npc_arrays
        @registry_dirty = false
      end
      @events.each do |id, event|
        token = @bodies[id]
        x,y=(event.real_x+0.5)*32,(event.real_y+0.5)*32
        sync_from(event) if (token.x-x).abs > 0.01 || (token.y-y).abs > 0.01
        actor = event.actor
        attach_actor(event) unless actor.is_a?(ContinuousSkills) && actor.instance_variable_get(:@fcp_combat).equal?(@combat)
        @bodies[id].hp = actor.health > 0 && actor.sta > -100 && actor.action_state != :death ? actor.health : 0
      end
    end

    def sync_from(event, token = body(event))
      return unless token
      token.x, token.y = (event.real_x + 0.5) * 32, (event.real_y + 0.5) * 32
      @orders.delete(event.id)
    end

    def request(event, x, y, target = nil, stop = 0)
      return false unless registered?(event)
      @orders[event.id] = [x, y, target, stop, event.move_type, event.is_follower? ? event.follower[1] : nil, NativeEffects.scripted == true]
      event.instance_variable_set(:@move_succeed, true)
      event.fcp_free_moving = true
      true
    end

    def step(event, dx, dy)
      token = body(event)
      length = Math.sqrt(dx * dx + dy * dy)
      return false if length == 0
      request(event, token.x + dx / length * 32, token.y + dy / length * 32)
    end

    def face_target(event, target = event.actor.get_target)
      return unless target
      token = body(event)
      x,y = @combat.effects.position(target)
      dx,dy = x-token.x,y-token.y
      length = Math.sqrt(dx*dx+dy*dy)
      return if length == 0
      token.facing_x,token.facing_y=dx/length,dy/length
      event.set_direction(dx.abs > dy.abs ? (dx > 0 ? 6 : 4) : (dy > 0 ? 2 : 8))
    end

    def toward(event, target)
      x, y = @combat.effects.position(target)
      request(event, x, y, target.respond_to?(:deleted?) ? target : nil, body(event).radius + @combat.effects.radius(target) + 3)
    end

    def tick(event)
      pending_route = false
      token, actor = body(event), event.actor
      # Native update may delete the NPC or change its page/region before this tick.
      return unless token
      old_x, old_y = token.x, token.y
      order = @orders[event.id]
      if order && (order[4] != event.move_type || (event.is_follower? && order[5] != event.follower[1]) ||
          (event.move_type == 6 && order[2] && !actor.get_target.equal?(order[2])))
        @orders.delete(event.id)
        order = nil
      end
      if order && @combat.available?(actor) && (order[6] || (actor.action_state != :skill && !@combat.recovery.busy?(actor)))
        x, y, target, stop = order
        if target
          if target.deleted? || target.actor && target.actor.action_state == :death
            @orders.delete(event.id)
            order = nil
          else
            x, y = @combat.effects.position(target)
          end
        end
        if order
          dx, dy = x - token.x, y - token.y
          distance = Math.sqrt(dx * dx + dy * dy)
          if distance <= [stop, 0.5].max
            @orders.delete(event.id)
          else
            speed = event.distance_per_frame * 32
            if @world.route_clear?(token, x, y, target && target_body(target))
              @routes.delete(event.id)
            else
              route = @routes[event.id]
              key = [(x / 16).floor, (y / 16).floor, @world.walls.object_id]
              if !route || route[0] != key || route[1] < Graphics.frame_count
                path = @world.route_between(token, x, y, target && target_body(target))
                pending_route = path.nil?
                unless pending_route
                  route = [key, Graphics.frame_count + 30, path]
                  @routes[event.id] = route
                end
              end
              route[2].shift while !pending_route && route[2].first && Math.sqrt((route[2][0][0] - token.x)**2 + (route[2][0][1] - token.y)**2) < speed
              if !pending_route && route[2].first
                dx, dy = route[2][0][0] - token.x, route[2][0][1] - token.y
                distance = Math.sqrt(dx * dx + dy * dy)
              end
            end
            if distance > 0 && !pending_route
              token.facing_x, token.facing_y = dx / distance, dy / distance
              event.set_direction(dx.abs > dy.abs ? (dx > 0 ? 6 : 4) : (dy > 0 ? 2 : 8))
              if event.trigger_in?([2])
                step = [speed, distance].min
                px = token.x + dx / distance * step - @world.player.x
                py = token.y + dy / distance * step - @world.player.y
                if px * px + py * py < (token.radius + @world.player.radius) ** 2
                  event.check_event_trigger_touch($game_player.x, $game_player.y)
                end
              end
              @world.move(token, dx / distance * [speed, distance].min, dy / distance * [speed, distance].min)
            end
          end
        end
      end
      event.fcp_free_moving = token.x != old_x || token.y != old_y
      @world.cancel_route(token) unless pending_route
      if order && !pending_route && !event.fcp_free_moving && actor.action_state != :skill && !@combat.recovery.busy?(actor)
        @orders.delete(event.id)
        event.instance_variable_set(:@move_succeed, false)
      end
      MapMode.session.sync_character(event, token)
    end
  end
end

if defined?(Game_Event) && defined?(FreeCombatPrototype::NativeCombat)
  module FreeCombatPrototype
    class NativeCombat
      attr_reader :npcs
      alias_method :npc_original_initialize, :initialize
      def initialize(world, opponent)
        npc_original_initialize(world, opponent)
        @npcs = MapNPCs.new(self, world, opponent)
      end
      alias_method :npc_original_update, :update
      def update(dx, dy, keyboard)
        @npcs.refresh
        npc_original_update(dx, dy, keyboard)
      end
    end
  end

  class Game_Event
    def fcp_npc_controller
      bridge = FreeCombatPrototype::NativeEffects.current
      controller = bridge && FreeCombatPrototype::MapMode.session.combat.npcs
      controller if controller && controller.registered?(self)
    end
    alias_method :npc_original_update, :update
    def update
      controller = fcp_npc_controller
      return npc_original_update unless controller
      combat = FreeCombatPrototype::MapMode.session.combat
      return if combat.paused && !FreeCombatPrototype::MapMode.story_npc_active?(self) &&
        !(FreeCombatPrototype::MapMode.story? && @move_route_forcing)
      FreeCombatPrototype::NativeEffects.with_source(self, false) { npc_original_update }
      if @fcp_native_step
        controller.sync_from(self)
        unless fcp_original_moving
          @fcp_native_step = nil
          self.fcp_free_moving = false
        end
      else
        controller.tick(self)
      end
    end
    alias_method :npc_original_routine_move, :update_routine_move
    def update_routine_move
      return npc_original_routine_move unless fcp_npc_controller && (move_route_forcing || combo_original_move_route)
      FreeCombatPrototype::NativeEffects.with_source(self) { npc_original_routine_move }
    end
    alias_method :npc_original_update_move, :update_move
    def update_move
      return if fcp_npc_controller && !@fcp_native_step
      npc_original_update_move
    end
    alias_method :npc_original_moveto, :moveto
    def moveto(x, y)
      controller = fcp_npc_controller
      token = controller && controller.body(self)
      @fcp_native_step = nil
      result = npc_original_moveto(x, y)
      controller.sync_from(self, token) if controller && token
      result
    end
    alias_method :npc_original_near, :near_the_target?
    def near_the_target?(target = $game_player, range = 10)
      bridge = FreeCombatPrototype::NativeEffects.current(self)
      return npc_original_near(target, range) unless fcp_npc_controller
      x,y = bridge.position(self); tx,ty = bridge.position(target)
      Math.sqrt((x-tx)**2+(y-ty)**2) <= (range - 1) * 32
    end
  end

  [[Game_Event, :move_toward_TargetSmartAI], [Game_Character, :move_toward_character]].each do |klass, name|
    klass.class_eval do
      original = ('npc_original_' + name.to_s).to_sym
      alias_method original, name
      define_method(name) do |target, *args|
        controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
        return controller.toward(self, target) if controller
        send(original, target, *args)
      end
    end
  end
  [[Game_Event, :move_toward_XY_SmartAI], [Game_Character, :move_goto_xy]].each do |klass, name|
    klass.class_eval do
      original = ('npc_original_' + name.to_s).to_sym
      alias_method original, name
      define_method(name) do |x, y, *args|
        controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
        return controller.request(self, (x+0.5)*32, (y+0.5)*32) if controller
        send(original, x, y, *args)
      end
    end
  end
  class Game_Character
    alias_method :npc_original_turn_toward, :turn_toward_character
    def turn_toward_character(target)
      result = npc_original_turn_toward(target)
      controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
      controller.face_target(self, target) if controller
      result
    end
    alias_method :npc_original_away, :move_away_from_character
    def move_away_from_character(target)
      controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
      if controller
        x,y = FreeCombatPrototype::NativeEffects.current.position(target)
        token = controller.body(self)
        return controller.step(self, token.x-x, token.y-y)
      end
      npc_original_away(target)
    end
  end

  class Game_CharacterBase
    alias_method :npc_original_straight_force, :move_straight_force
    def move_straight_force(direction)
      controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
      return npc_original_straight_force(direction) unless controller
      # Scripted force steps retain native interpolation and may cross impassable tiles.
      @fcp_native_step = true
      result = npc_original_straight_force(direction)
      controller.sync_from(self)
      token = controller.body(self)
      token.facing_x, token.facing_y = {2=>[0,1],4=>[-1,0],6=>[1,0],8=>[0,-1]}[direction] if token
      result
    end
    alias_method :npc_original_straight, :move_straight
    alias_method :npc_original_diagonal, :move_diagonal
    def move_straight(direction, turn_ok = true)
      controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
      if controller
        set_direction(direction) if turn_ok
        dx,dy = {2=>[0,1],4=>[-1,0],6=>[1,0],8=>[0,-1]}[direction]
        return controller.step(self, dx, dy)
      end
      npc_original_straight(direction, turn_ok)
    end
    def move_diagonal(horizontal, vertical)
      controller = respond_to?(:fcp_npc_controller) && fcp_npc_controller
      return controller.step(self, horizontal == 4 ? -1 : 1, vertical == 8 ? -1 : 1) if controller
      npc_original_diagonal(horizontal, vertical)
    end
  end
end
