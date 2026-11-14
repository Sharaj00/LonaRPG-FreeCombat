module FreeCombatPrototype
  module SkillGeometry
    def self.cardinal(dx, dy)
      dx.abs > dy.abs ? [dx < 0 ? -1.0 : 1.0, 0.0] : [0.0, dy < 0 ? -1.0 : 1.0]
    end

    def self.weight(sensor, sx, sy, fx, fy, tx, ty, radius)
      cells = sensor.instance_variable_get(:@fcp_hit_cells)
      unless cells
        cy, cx = sensor.center
        cells = []
        sensor.detection_array.each_with_index do |row, y|
          row.each_with_index do |value, x|
            value = value[1] if value.is_a?(Array)
            cells << [x - cx, y - cy, value] if value && value > 0
          end
        end
        sensor.instance_variable_set(:@fcp_hit_cells, cells)
      end
      bounds = sensor.instance_variable_get(:@fcp_hit_bounds)
      unless bounds
        xs, ys = cells.map { |cell| cell[0] }, cells.map { |cell| cell[1] }
        bounds = cells.empty? ? [] : [xs.min - 0.5, ys.min - 0.5, xs.max + 0.5, ys.max + 0.5]
        sensor.instance_variable_set(:@fcp_hit_bounds, bounds)
      end
      dx, dy = (tx - sx) / 32.0, (ty - sy) / 32.0
      x, y = dx * fy - dy * fx, dx * fx + dy * fy
      # A forward battle mask includes the user's cell, but its radius-expanded
      # rear edge must not hit a victim whose center is behind the attacker.
      # Keep explicit rear/circular masks and single-cell floor/projectile effects.
      if y < -1.0e-9 && defined?(Sensors::Battle_Sensor) && sensor.is_a?(Class) && sensor <= Sensors::Battle_Sensor
        return 0 if cells.any? { |cell| cell[1] > 0 } && cells.none? { |cell| cell[1] < 0 }
      end
      r = radius / 32.0
      radius_squared = r * r
      return 0 if bounds.empty?
      if x.finite? && y.finite?
        return 0 if (x < bounds[0] && (x - bounds[0]) ** 2 > radius_squared) ||
          (x > bounds[2] && (x - bounds[2]) ** 2 > radius_squared) ||
          (y < bounds[1] && (y - bounds[1]) ** 2 > radius_squared) ||
          (y > bounds[3] && (y - bounds[3]) ** 2 > radius_squared)
      end
      cells.inject(0) do |weight, (cx, cy, value)|
        px, py = [[x, cx - 0.5].max, cx + 0.5].min, [[y, cy - 0.5].max, cy + 0.5].min
        (x - px) ** 2 + (y - py) ** 2 <= radius_squared ? [weight, value].max : weight
      end
    end

    def self.advance(shot, world, targets, collide_walls = true)
      shot.life -= 1
      steps = [(Math.sqrt(shot.dx ** 2 + shot.dy ** 2) / 2.0).ceil, 1].max
      steps.times do
        shot.x += shot.dx / steps
        shot.y += shot.dy / steps
        return :wall if collide_walls && world.blocked?(shot.x, shot.y, 4)
        targets.each do |character, x, y, radius|
          return character if (shot.x - x) ** 2 + (shot.y - y) ** 2 <= (radius + 4) ** 2
        end
      end
      shot.life <= 0 ? :expired : nil
    end
  end

  class NativeEffects
    attr_reader :events
    class << self
      attr_accessor :source, :scripted
    end

    def self.with_source(character, scripted = true)
      previous, previous_scripted = source, self.scripted
      self.source, self.scripted = character, scripted
      yield
    ensure
      self.source, self.scripted = previous, previous_scripted
    end

    def self.projectile_ignored?(actor)
      actor.is_projectile || actor.immune_damage || actor.action_state == :death ||
        (actor.respond_to?(:ignore_projectile) && actor.ignore_projectile)
    end

    def self.current(character = nil)
      return nil unless defined?(MapMode) && MapMode.active?
      combat = MapMode.session.combat
      bridge = combat && combat.effects
      bridge if bridge && (!character || bridge.owns?(character))
    end

    def initialize(combat, world, opponent)
      @combat, @world, @opponent, @player = combat, world, opponent, $game_player
      @events, @projectiles, @selectors, @miles = {}, {}, {}, {}
    end

    def training_target?(character)
      character && character.respond_to?(:actor) && character.actor && character.actor.respond_to?(:npc_name) &&
        character.actor.npc_name == 'NeutralSandbagImmortal'
    end

    def npc_body(character)
      @combat.respond_to?(:npcs) && @combat.npcs && @combat.npcs.body(character)
    end

    def owns?(character, depth = 0)
      return false unless character && depth < 16
      return true if npc_body(character)
      return true if character.equal?(@player) || (character.equal?(@opponent) && !(@combat.respond_to?(:npcs) && @combat.npcs)) || training_target?(character)
      return true if character.instance_variable_get(:@fcp_effects).equal?(self)
      data = character.respond_to?(:summon_data) && character.summon_data
      data && owns?(data[:user] || data[:fcp_owner], depth + 1)
    end

    def characters
      ([@player] + (@combat.respond_to?(:npcs) && @combat.npcs ? [] : [@opponent]) + (@combat.respond_to?(:npcs) && @combat.npcs ? @combat.npcs.events.values : []) + @events.values + $game_map.events.values.select { |event| training_target?(event) || (event.actor && event.actor.is_object) }).uniq.select do |event|
        event.respond_to?(:actor) && event.actor && !event.erased && !event.deleted?
      end
    end

    def target?(event)
      owns?(event) || (event && event.respond_to?(:actor) && event.actor && event.actor.is_object &&
        $game_map.events[event.id].equal?(event) && !event.erased && !event.deleted?)
    end

    def position(character)
      token = npc_body(character)
      return [token.x, token.y] if token
      return [@world.player.x, @world.player.y] if character.equal?(@player)
      return [@world.enemy.x, @world.enemy.y] if character.equal?(@opponent) && !(@combat.respond_to?(:npcs) && @combat.npcs)
      [( (character.respond_to?(:real_x) ? character.real_x : character.x) + 0.5) * 32,
       ( (character.respond_to?(:real_y) ? character.real_y : character.y) + 0.5) * 32]
    end

    def facing(character)
      body = npc_body(character) || (character.equal?(@player) ? @world.player : (character.equal?(@opponent) ? @world.enemy : nil))
      return [body.facing_x, body.facing_y] if body
      shot = @projectiles[character.id] if character.respond_to?(:id)
      if shot
        length = Math.sqrt(shot.dx ** 2 + shot.dy ** 2)
        return [shot.dx / length, shot.dy / length] if length > 0
      end
      stored = character.instance_variable_get(:@fcp_facing)
      return stored if stored && character.direction == character.instance_variable_get(:@fcp_direction)
      {2 => [0, 1], 4 => [-1, 0], 6 => [1, 0], 8 => [0, -1]}[character.direction] || [0, 1]
    end

    def radius(character)
      token = npc_body(character)
      token ? token.radius : (character.equal?(@player) ? @world.player.radius : @world.enemy.radius)
    end

    def weight(sensor, character, target, track)
      sx, sy = position(character)
      tx, ty = position(target)
      fx, fy = track ? [0, 1] : facing(character)
      value = SkillGeometry.weight(sensor, sx, sy, fx, fy, tx, ty, radius(target))
      value > 0 ? value : nil
    end

    def sight(sensor, character, target)
      sx, sy = position(character)
      tx, ty = position(target)
      hp = @world.without_event_walls([character, target]) { @world.clear_line?(sx, sy, tx, ty) } ? sensor.sight_hp : -1
      [hp, Math.sqrt((tx - sx) ** 2 + (ty - sy) ** 2) / 32.0]
    end

    def sync(event, body)
      MapMode.session.sync_character(event, body)
    end

    def register(event, data)
      return unless data && owns?(data[:user] || data[:fcp_owner])
      event.instance_variable_set(:@fcp_effects, self)
      @events[event.id] = event
      # Native trap sensors must still see owned floor effects such as lantern fire.
      $game_map.delete_npc(event) if event.actor && event.actor.is_projectile
      anchor(event)
      user = data[:user] || data[:fcp_owner]
      if user && event.direction == user.direction
        event.instance_variable_set(:@fcp_facing, facing(user))
        event.instance_variable_set(:@fcp_direction, event.direction)
      end
      if event.actor && event.actor.respond_to?(:is_projectile) && event.actor.is_projectile
        start_projectile(event, data)
      end
    end

    def anchor(event)
      return if event.instance_variable_get(:@fcp_native_anchor_handled)
      data = event.summon_data
      return unless data
      user, target = data[:user] || data[:fcp_owner], data[:target]
      if @last_aim && data[:tgt_x] == @last_aim[0] && data[:tgt_y] == @last_aim[1]
        x, y = @last_aim[2], @last_aim[3]
      elsif target && target.respond_to?(:real_x) && event.x == target.x && event.y == target.y
        x, y = position(target)
      elsif user && event.real_x == event.x && event.real_y == event.y
        ux, uy = position(user)
        x, y = ux + (event.x - user.x) * 32, uy + (event.y - user.y) * 32
      else
        return
      end
      event.instance_variable_set(:@real_x, x / 32.0 - 0.5)
      event.instance_variable_set(:@real_y, y / 32.0 - 0.5)
    end

    def start_projectile(event, data)
      actor = event.actor
      skill = data[:skill]
      x, y = position(event)
      fx, fy = facing(event)
      if actor.target
        tx, ty = (actor.target.x + 0.5) * 32, (actor.target.y + 0.5) * 32
        dx, dy = tx - x, ty - y
        length = Math.sqrt(dx * dx + dy * dy)
        fx, fy = dx / length, dy / length if length > 0
      end
      # Player aim and NPC target tracking share the same four shooting axes.
      # Resolve exact diagonal ties vertically, matching native sprite facing.
      fx, fy = SkillGeometry.cardinal(fx, fy)
      event.set_direction(fx.abs > fy.abs ? (fx > 0 ? 6 : 4) : (fy > 0 ? 2 : 8))
      speed = 2.0 ** actor.move_speed / 8.0
      range = actor.instance_variable_get(:@range) || (skill && skill.range) || 5
      shot = NativeShot.new(x, y, fx * speed, fy * speed, [(range * 32 / speed).ceil, 1].max, actor, skill)
      @projectiles[event.id], @miles[event.id] = shot, 0.0
    end

    def projectile?(event)
      @projectiles.has_key?(event.id)
    end

    def curved_displacement(event, dx, dy)
      data = event.respond_to?(:summon_data) && event.summon_data
      skill = data && data[:skill]
      return nil unless skill && skill.projectile_type == 2 && data[:user] && !event.equal?(data[:user])
      return nil unless event.actor && event.actor.respond_to?(:user_redirect) && event.actor.user_redirect
      return nil if npc_body(event) || event.equal?(@player) || (event.actor && event.actor.is_projectile)
      # Native lobbed arrows are SkillDummy events using jump_to, not registered
      # projectiles. Preserve the native jump distance/arc, but use one firing axis.
      distance = Math.sqrt(dx * dx + dy * dy).round
      fx, fy = SkillGeometry.cardinal(dx, dy)
      [fx.to_i * distance, fy.to_i * distance]
    end

    def projectile_distance(event)
      @miles[event.id] / 32.0
    end

    def update_projectile(event)
      return if @combat.paused
      shot, actor = @projectiles[event.id], event.actor
      event.update_delete_frame
      return if event.deleted?
      event.update_character_ex_effects
      event.update_animation
      event.update_animation_synced
      event.update_routine_move if event.move_route_forcing || event.move_type == 3
      actor.update_state_frames
      actor.update_skill_eff if actor.action_state == :skill
      user = event.summon_data[:user]
      effective = actor.projectile_type != 2 || projectile_distance(event) >= actor.effect_since
      targets = effective ? characters.reject do |target|
        target.equal?(user) || target.equal?(event) || NativeEffects.projectile_ignored?(target.actor) ||
          (user && user.actor && user.actor.friendly?(target))
      end.map { |target| [target, *position(target), radius(target)] } : []
      result = @world.without_event_walls(targets.map { |entry| entry[0] }) { SkillGeometry.advance(shot, @world, targets, effective) }
      @miles[event.id] += Math.sqrt(shot.dx ** 2 + shot.dy ** 2)
      sync(event, shot)
      return unless result
      if !result.is_a?(Symbol)
        shot.x, shot.y = position(result)
        sync(event, shot)
      end
      NativeEffects.with_source(event) do
        actor.set_killer_skill(0)
        actor.missile_auto_ded unless event.deleted?
      end
      prune
    end

    def capture_aim
      event = @player.crosshair
      return unless event && owns?(event)
      x, y = position(event)
      @last_aim = [event.x, event.y, x, y]
    end

    def update_selector(dx, dy)
      event = @player.crosshair
      return [dx, dy] unless event && owns?(event)
      if defined?(Mouse) && Mouse.enable?
        @player.move_crosshair_by_input
      else
        move_selector(event, dx, dy)
      end
      [0, 0]
    end

    def move_selector(event, dx, dy)
      x, y = position(event)
      body = @selectors[event.id] ||= Body.new(x, y, 0, 1, 0, 1, 0)
      length = Math.sqrt(dx * dx + dy * dy)
      if length > 0
        nx, ny = body.x + dx / length * 2.6, body.y + dy / length * 2.6
        px, py = position(@player)
        range = event.instance_variable_get(:@selector_range)
        if range.nil? || range < 0 || (nx - px).abs + (ny - py).abs <= range * 32
          body.x, body.y = nx, ny
        end
      end
      sync(event, body)
      px, py = position(@player)
      dx, dy = body.x - px, body.y - py
      length = Math.sqrt(dx * dx + dy * dy)
      if length > 0
        @world.player.facing_x, @world.player.facing_y = dx / length, dy / length
        MapMode.session.face(@player, dx, dy)
      end
      capture_aim
    end

    def prune
      @events.delete_if do |id, event|
        gone = event.deleted? || !$game_map.events[id].equal?(event)
        if gone
          @projectiles.delete(id)
          @selectors.delete(id)
          @miles.delete(id)
        end
        gone
      end
    end

    def dispose(preserve_npcs = false)
      @events.values.each do |event|
        next unless $game_map.events[event.id].equal?(event) && !event.deleted?
        if preserve_npcs && event.actor && !event.actor.is_object && !event.actor.is_projectile
          event.instance_variable_set(:@fcp_effects, nil)
        else
          event.delete
        end
      end
      @player.cancel_crosshair if @player.crosshair && owns?(@player.crosshair)
      queue = $game_map.instance_variable_get(:@summoned_evs)
      queue.delete_if { |name, x, y, id, data| data && owns?(data[:user] || data[:fcp_owner]) } if queue
    end
  end
end

if defined?(Game_Map) && defined?(Sensors::Basic_Sensor)
  class << Sensors::Basic_Sensor
    alias_method :fcp_effect_scan, :scan
    alias_method :fcp_effect_sense, :sense
    alias_method :fcp_effect_signal, :get_signal
    alias_method :fcp_effect_mine, :mine_number
    alias_method :fcp_effect_sight, :calc_sight_hp_and_dist
    def scan(character, targets = nil)
      bridge = FreeCombatPrototype::NativeEffects.current(character)
      center if bridge
      fcp_effect_scan(character, targets || (bridge ? (bridge.characters + [character]).uniq : $game_map.all_characters))
    end
    def sense(character, targets = nil)
      bridge = FreeCombatPrototype::NativeEffects.current(character)
      center if bridge
      fcp_effect_sense(character, targets || (bridge ? (bridge.characters + [character]).uniq : $game_map.all_characters))
    end
    def get_signal(character, target, track = false)
      bridge = FreeCombatPrototype::NativeEffects.current(character)
      return 0 if bridge && !bridge.target?(target)
      center if bridge
      fcp_effect_signal(character, target, track)
    end
    def mine_number(character, target, track)
      bridge = FreeCombatPrototype::NativeEffects.current(character)
      bridge ? bridge.weight(self, character, target, track) : fcp_effect_mine(character, target, track)
    end
    def calc_sight_hp_and_dist(character, target)
      bridge = FreeCombatPrototype::NativeEffects.current(character)
      bridge ? bridge.sight(self, character, target) : fcp_effect_sight(character, target)
    end
  end

  class Game_Map
    alias_method :fcp_effect_ask_summon, :ask_summon_event
    alias_method :fcp_effect_reserve, :reserve_summon_event
    alias_method :fcp_effect_summon_skill, :summon_skill
    alias_method :fcp_effect_refresh_npcs, :refresh_npc_arrays
    def ask_summon_event(name, x = nil, y = nil, id = -1, data = nil)
      owner = data && (data[:user] || data[:fcp_owner])
      bridge = owner && FreeCombatPrototype::NativeEffects.current(owner)
      event = if bridge
        FreeCombatPrototype::NativeEffects.with_source(owner) { fcp_effect_ask_summon(name, x, y, id, data) }
      else
        fcp_effect_ask_summon(name, x, y, id, data)
      end
      bridge = FreeCombatPrototype::NativeEffects.current
      bridge.register(event, data) if bridge && event
      event
    end
    def reserve_summon_event(name, x = $game_player.x, y = $game_player.y, id = -1, data = nil)
      source = FreeCombatPrototype::NativeEffects.source
      if FreeCombatPrototype::NativeEffects.current(source) && source
        data = (data || {}).dup
        data[:fcp_owner] ||= source
      end
      fcp_effect_reserve(name, x, y, id, data)
    end
    def summon_skill(name, data = nil, id = -1)
      source = FreeCombatPrototype::NativeEffects.source
      if FreeCombatPrototype::NativeEffects.current(source) && source
        data = (data || {}).dup
        data[:fcp_owner] ||= source
      end
      fcp_effect_summon_skill(name, data, id)
    end
    def refresh_npc_arrays
      result = fcp_effect_refresh_npcs
      bridge = FreeCombatPrototype::NativeEffects.current
      bridge.events.values.each { |event| delete_npc(event) if event.actor && event.actor.is_projectile } if bridge
      result
    end
  end

  class Game_Interpreter
    alias_method :fcp_effect_update, :update
    def update
      event = $game_map.events[@event_id]
      bridge = event && FreeCombatPrototype::NativeEffects.current(event)
      if bridge
        return FreeCombatPrototype::NativeEffects.with_source(event) { fcp_effect_update }
      end
      fcp_effect_update
    end
  end

  class Game_Event
    alias_method :fcp_effect_move_selector, :move_selector
    def move_selector(direction)
      bridge = FreeCombatPrototype::NativeEffects.current(self)
      return fcp_effect_move_selector(direction) unless bridge && self.equal?($game_player.crosshair)
      motion = {2=>[0,1],4=>[-1,0],6=>[1,0],8=>[0,-1]}[direction]
      bridge.move_selector(self, *motion) if motion
    end

    alias_method :fcp_effect_update, :update
    alias_method :fcp_effect_moveto, :moveto
    def update
      return if FreeCombatPrototype::MapMode.pause_blocks?(self)
      bridge = FreeCombatPrototype::NativeEffects.current(self)
      if bridge && !self.equal?($game_player) && !self.equal?(FreeCombatPrototype::MapMode.session.opponent) && !bridge.npc_body(self)
        return if FreeCombatPrototype::MapMode.session.combat.paused
        return bridge.update_projectile(self) if bridge.projectile?(self)
        return FreeCombatPrototype::NativeEffects.with_source(self) { fcp_effect_update }
      end
      fcp_effect_update
    end
    alias_method :fcp_pause_update_npc, :update_npc
    def update_npc
      return if FreeCombatPrototype::MapMode.paused?
      fcp_pause_update_npc
    end
    def moveto(x, y)
      result = fcp_effect_moveto(x, y)
      bridge = FreeCombatPrototype::NativeEffects.current(self)
      bridge.anchor(self) if bridge
      result
    end
  end

  [Game_Player, Game_Event].each do |klass|
    klass.class_eval do
      alias_method :fcp_effect_fake_target, :get_fake_target
      def get_fake_target
        bridge = FreeCombatPrototype::NativeEffects.current(self)
        return fcp_effect_fake_target unless bridge
        fx, fy = bridge.facing(self)
        reach = [$game_map.width, $game_map.height].max
        Struct::FakeTarget.new(x + (fx * reach).round, y + (fy * reach).round)
      end
    end
  end

  class Game_PorjectileCharacter
    alias_method :fcp_effect_mileage, :cur_mileage
    def cur_mileage
      bridge = FreeCombatPrototype::NativeEffects.current(map_token)
      bridge && bridge.projectile?(map_token) ? bridge.projectile_distance(map_token) : fcp_effect_mileage
    end
  end

  [Game_Actor, Game_NonPlayerCharacter].each do |klass|
    klass.class_eval do
      alias_method :fcp_effect_take_skill, :take_skill_effect
      def take_skill_effect(user, skill, can_sap = false, force_hit = false)
        bridge = FreeCombatPrototype::NativeEffects.current(user.map_token)
        result = fcp_effect_take_skill(user, skill, can_sap, force_hit)
        if bridge
          combat = FreeCombatPrototype::MapMode.session.combat
          combat.sync_health
        end
        result
      end
    end
  end

  class Game_CharacterBase
    alias_method :fcp_effect_straight, :move_straight
    alias_method :fcp_effect_diagonal, :move_diagonal
    def move_straight(direction, turn_ok = true)
      @fcp_native_motion = true if FreeCombatPrototype::NativeEffects.current(self)
      fcp_effect_straight(direction, turn_ok)
    end
    def move_diagonal(horizontal, vertical)
      @fcp_native_motion = true if FreeCombatPrototype::NativeEffects.current(self)
      fcp_effect_diagonal(horizontal, vertical)
    end
  end

  class Game_Character
    alias_method :fcp_effect_atk_sync, :atkEFX_XY_sync
    alias_method :fcp_effect_atk_center, :atkEFX_XY_sync_center
    def atkEFX_XY_sync(user, fix = 25)
      @fcp_native_anchor_handled = true if FreeCombatPrototype::NativeEffects.current(self)
      fcp_effect_atk_sync(user, fix)
    end
    def atkEFX_XY_sync_center(user)
      @fcp_native_anchor_handled = true if FreeCombatPrototype::NativeEffects.current(self)
      fcp_effect_atk_center(user)
    end
    alias_method :fcp_effect_jump, :jump
    alias_method :fcp_effect_jump_low, :jump_low
    def jump(dx, dy, peak = 10)
      bridge = FreeCombatPrototype::NativeEffects.current
      curved = bridge && bridge.curved_displacement(self, dx, dy)
      return fcp_effect_jump(curved[0], curved[1], peak) if curved
      return fcp_effect_jump(dx, dy, peak) unless FreeCombatPrototype::MapMode.controls?(self)
      session = FreeCombatPrototype::MapMode.session
      return fcp_effect_jump(dx, dy, peak) unless FreeCombatPrototype::NativeEffects.source
      body = session.combat.effects.npc_body(self) || (self.equal?($game_player) ? session.world.player : session.world.enemy)
      session.world.move(body, dx * 32, dy * 32)
      session.sync_character(self, body)
    end
    def jump_low(dx, dy, peak = 5)
      return fcp_effect_jump_low(dx, dy, peak) unless FreeCombatPrototype::MapMode.controls?(self) && FreeCombatPrototype::NativeEffects.source
      jump(dx, dy, peak)
    end
  end

  class << SceneManager
    alias_method :fcp_effect_goto, :goto
    def goto(scene_class)
      if defined?(FreeCombatPrototype::MapMode) && FreeCombatPrototype::MapMode.enabled? && scene_class == Scene_Map
        scene_class = Scene_FreeCombatMap
      end
      fcp_effect_goto(scene_class)
    end
  end
end
