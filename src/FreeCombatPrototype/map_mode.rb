module FreeCombatPrototype
  module MapMode
    class << self
      attr_reader :session, :target_map_id
      attr_accessor :travel_recovery
    end

    def self.enabled?
      @enabled == true
    end

    def self.story?
      enabled? && @story == true
    end

    def self.start_story
      release
      data = StorySaves.pending
      @enabled, @story = true, true
      @paused = data.is_a?(Hash) && data[:paused] == true
      @travel_recovery = data.is_a?(Hash) ? data[:travel_recovery] : nil
    end

    def self.active?
      enabled? && @session && $game_map.map_id == @target_map_id && @session.map_data.equal?($game_map.instance_variable_get(:@map)) && @session.contains_player?
    end

    def self.controls?(character)
      active? && (character.equal?($game_player) || ((@session.combat.respond_to?(:npcs) && @session.combat.npcs) ? @session.combat.npcs.registered?(character) : character.equal?(@session.opponent)))
    end

    def self.paused?
      enabled? && $game_map && !$game_map.isOverMap && pause_state
    end

    def self.pause_state
      @session ? @session.combat.paused : @paused == true
    end

    def self.story_npc_active?(event)
      story? && $game_map.interpreter.running? && event.respond_to?(:force_update_actor) &&
        event.force_update && event.force_update_actor == false && event.actor &&
        !event.actor.is_object && !event.actor.is_projectile
    end

    def self.pause_blocks?(event)
      paused? && !story_npc_active?(event) && !(story? && event.move_route_forcing) &&
        (event.actor || (@session && @session.combat.effects.owns?(event)))
    end

    def self.prepare
      return unless enabled?
      if $game_map.isOverMap
        release
        return
      end
      pending = story? && StorySaves.pending
      restoring = pending.is_a?(Hash) && pending[:map_id] == $game_map.map_id
      return if !restoring && ($game_map.interpreter.running? || $game_message.busy?)
      return if active? && !@session.geometry_changed?
      retained = StorySaves.capture if story? && @session && @session.map_data.equal?($game_map.instance_variable_get(:@map))
      release(!retained)
      StorySaves.pending = retained if retained
      @target_map_id = $game_map.map_id
      @session = MapSession.new
      @session.combat.instance_variable_set(:@paused, @paused)
      if @travel_recovery
        actor = $game_player.actor
        @session.combat.recovery.instance_variable_get(:@actions)[actor.object_id] = [actor, @travel_recovery]
        @travel_recovery = nil
      end
      StorySaves.resume_controller if story?
    end

    def self.release(dispose_effects = true)
      if @session
        @paused = @session.combat.paused if @session.combat
        if dispose_effects && @session.combat && @session.combat.effects
          story? ? @session.combat.effects.dispose(true) : @session.combat.effects.dispose
        end
        if @session.combat && @session.combat.respond_to?(:npcs) && @session.combat.npcs
          combat = @session.combat
          actors = [combat.instance_variable_get(:@player)] + combat.npcs.events.values.map { |event| event.actor }
          actors.compact.each do |actor|
            actor.instance_variable_set(:@fcp_combat, nil) if actor && actor.instance_variable_get(:@fcp_combat).equal?(@session.combat)
          end
          player = combat.effects.instance_variable_get(:@player)
          ([player] + combat.npcs.events.values).compact.each do |event|
            event.fcp_free_moving = false
          end
          combat.effects.events.values.each { |event| event.instance_variable_set(:@fcp_effects, nil) }
        end
      end
      @session = nil
    end

    def self.stop
      release
      @enabled = false
      @story = false
      @travel_recovery = nil
    end
  end

  class MapSession
    attr_reader :world, :opponent, :keyboard, :map_data, :last_direction, :combat
    attr_accessor :native_motion

    def initialize
      @map_data = $game_map.instance_variable_get(:@map)
      @geometry_signature = geometry_signature
      px, py = ($game_player.real_x + 0.5) * 32, ($game_player.real_y + 0.5) * 32
      @world = MapWorld.new($game_map, px, py, px, py)
      @world.refresh_event_walls($game_map.events.values, nil)
      @opponent = nil
      @world.enemy.hp = 0
      @combat = NativeCombat.new(@world, @opponent)
      @keyboard = Keyboard.new
      @keyboard.update
      @native_motion = false
      sync_from_player
    end

    def contains_player?
      @world.geometry.include?($game_player.x, $game_player.y)
    end

    def geometry_signature
      [$game_map.tileset.object_id, $game_map.forced_block_dir.dup,
       ($game_map.instance_variable_get(:@tile_events) || []).map { |e| [e.x, e.y, e.tile_id] }]
    end

    def geometry_changed?
      @geometry_signature != geometry_signature
    end

    def suspended?
      $game_map.interpreter.running? || $game_message.busy? || $game_message.visible ||
        $game_player.instance_variable_get(:@move_route_forcing) || $game_player.jumping? || $game_player.cannot_control || $game_pause
    end

    def sync_from_player
      @world.player.x = ($game_player.real_x + 0.5) * 32
      @world.player.y = ($game_player.real_y + 0.5) * 32
      @last_direction = $game_player.direction
      facing = {2 => [0, 1], 4 => [-1, 0], 6 => [1, 0], 8 => [0, -1]}[$game_player.direction]
      @world.player.facing_x, @world.player.facing_y = facing if facing
    end

    def sync_character(character, body)
      old_x, old_y = character.x, character.y
      x, y = (body.x / 32).floor, (body.y / 32).floor
      indexed = !character.equal?($game_player) && $game_map.events[character.id].equal?(character)
      $game_map.delete_event_from_pos_hash(character) if indexed && (old_x != x || old_y != y)
      character.instance_variable_set(:@x, x)
      character.instance_variable_set(:@y, y)
      character.instance_variable_set(:@real_x, body.x / 32.0 - 0.5)
      character.instance_variable_set(:@real_y, body.y / 32.0 - 0.5)
      $game_map.add_event_to_pos_hash(character) if indexed && (old_x != x || old_y != y)
    end

    def face(character, dx, dy)
      return if dx == 0 && dy == 0
      character.set_direction(dx.abs > dy.abs ? (dx > 0 ? 6 : 4) : (dy > 0 ? 2 : 8))
      @last_direction = character.direction if character.equal?($game_player)
    end

    def update_camera(last_x = nil, last_y = nil)
      player = $game_player
      if $game_map.cam_target > 0
        target = $game_map.events[$game_map.cam_target]
        $game_map.set_event_display_pos(target.real_x - player.center_x, target.real_y - player.center_y)
      elsif last_x
        player.update_scroll(last_x, last_y)
      end
    end

    def update_player
      update_keyboard
      @world.refresh_event_walls($game_map.events.values.reject { |event| (@combat.effects.events.has_key?(event.id) || (@combat.respond_to?(:npcs) && @combat.npcs && @combat.npcs.registered?(event))) }, @opponent)
      player = $game_player
      if MapMode.story? && !@combat.paused
        player.process_movement_inputs_normal
        player.process_camera_movement_input
        player.process_portrait_inputs
        player.process_light_update
      end
      previous_cell = [player.x, player.y]
      px, py = @world.player.x, @world.player.y
      dx = (@keyboard.down?(:right) ? 1 : 0) - (@keyboard.down?(:left) ? 1 : 0)
      dy = (@keyboard.down?(:down) ? 1 : 0) - (@keyboard.down?(:up) ? 1 : 0)
      face(player, dx, dy) unless player.actor.action_state == :skill || @combat.paused
      @combat.update(dx, dy, @keyboard)
      return unless MapMode.active? && MapMode.session.equal?(self)
      sync_character(player, @world.player)
      player.fcp_free_moving = @world.player.x != px || @world.player.y != py
      player.instance_variable_set(:@stop_count, player.fcp_free_moving ? 0 : player.instance_variable_get(:@stop_count).to_i + 1)
      unless @combat.paused
        player.update_character_ex_effects
        player.update_animation
        player.update_animation_synced
      end
      player.update_bush_depth
      update_camera(px / 32.0 - 0.5, py / 32.0 - 0.5)
      unless @combat.paused
        distance = player.instance_variable_get(:@fcp_stride_distance).to_f +
          Math.sqrt((@world.player.x - px) ** 2 + (@world.player.y - py) ** 2)
        while distance >= 32
          distance -= 32
          player.increase_steps if MapMode.story?
          player.handle_on_move
          $game_party.on_player_walk
        end
        player.instance_variable_set(:@fcp_stride_distance, distance)
        player.check_touch_event if previous_cell != [player.x, player.y]
      end
      return unless MapMode.active?
      player.update_target if MapMode.story?
      if @keyboard.trigger?(:interact) || @keyboard.trigger?(:enter)
        player.check_action_event(true)
      elsif !@combat.paused && (dx != 0 || dy != 0) && !player.fcp_free_moving
        player.check_event_trigger_touch_front
      end
    end

    def update_keyboard
      return if @keyboard_frame == Graphics.frame_count
      @keyboard_frame = Graphics.frame_count
      @keyboard.update
    end
  end
end

if defined?(Game_Map)
  class Game_Map
    alias_method :fcp_pause_update_events, :update_events
    def update_events
      mode = FreeCombatPrototype::MapMode
      if mode.active?
        session = mode.session
        session.update_keyboard
        session.combat.update_pause(session.keyboard) unless session.suspended? || !$game_player.force_update
      end
      fcp_pause_update_events
    end
    alias_method :fcp_original_setup, :setup
    def setup(map_id)
      mode = FreeCombatPrototype::MapMode
      if mode.story? && mode.session
        combat = mode.session.combat
        player = combat.instance_variable_get(:@player)
        action = combat.recovery.instance_variable_get(:@actions)[player.object_id]
        mode.travel_recovery = action && action[1]
      end
      FreeCombatPrototype::MapMode.release if FreeCombatPrototype::MapMode.enabled?
      fcp_original_setup(map_id)
    end

    alias_method :fcp_original_refresh_npc_arrays, :refresh_npc_arrays
    def refresh_npc_arrays
      result = fcp_original_refresh_npc_arrays
      mode = FreeCombatPrototype::MapMode
      delete_npc(mode.session.opponent) if mode.active? && !(mode.session.combat.respond_to?(:npcs) && mode.session.combat.npcs)
      result
    end
  end
end

class Game_CharacterBase
  attr_accessor :fcp_free_moving
  alias_method :fcp_original_moving, :moving?
  def moving?
    return fcp_original_moving if @fcp_native_step
    bridge = FreeCombatPrototype::NativeEffects.current(self)
    if bridge && !FreeCombatPrototype::MapMode.controls?(self)
      return false unless @fcp_native_motion
      moving = fcp_original_moving
      @fcp_native_motion = false unless moving
      return moving
    end
    if FreeCombatPrototype::MapMode.controls?(self) &&
        (!self.equal?($game_player) || !FreeCombatPrototype::MapMode.session.native_motion)
      return @fcp_free_moving == true
    end
    fcp_original_moving
  end
end

class Game_Player
  alias_method :fcp_pause_normalmap, :update_normalmap
  def update_normalmap
    return if FreeCombatPrototype::MapMode.paused?
    fcp_pause_normalmap
  end
  alias_method :fcp_pause_action_state, :update_action_state
  def update_action_state
    return if FreeCombatPrototype::MapMode.paused?
    fcp_pause_action_state
  end
  alias_method :fcp_original_update, :update
  alias_method :fcp_original_moveto, :moveto
  def update
    mode = FreeCombatPrototype::MapMode
    return fcp_original_update unless mode.active?
    session = mode.session
    unless @force_update
      session.update_keyboard
      self.fcp_free_moving = false
      result = fcp_original_update
      session.sync_from_player if mode.active?
      return result
    end
    if session.suspended?
      # Consume edges during native scenes so held attacks do not become queued presses.
      session.update_keyboard
      body = session.world.player
      changed = x != (body.x / 32).floor || y != (body.y / 32).floor ||
        ((real_x + 0.5) * 32 - body.x).abs > 0.01 || ((real_y + 0.5) * 32 - body.y).abs > 0.01
      if @move_route_forcing || jumping? || cannot_control || changed
        begin
          session.native_motion = true
          fcp_original_update
          session.sync_from_player if mode.active?
        ensure
          session.native_motion = false
        end
      else
        self.fcp_free_moving = false
        session.update_camera
        update_animation unless session.combat.paused
        session.sync_from_player if direction != session.last_direction
      end
    else
      session.update_player
    end
  end
  def moveto(x, y)
    result = fcp_original_moveto(x, y)
    FreeCombatPrototype::MapMode.session.sync_from_player if FreeCombatPrototype::MapMode.active?
    result
  end
end

class Game_Actor
  alias_method :fcp_pause_state_frames, :update_state_frames
  def update_state_frames
    return if FreeCombatPrototype::MapMode.paused?
    fcp_pause_state_frames
  end
end

class Game_Event
  alias_method :fcp_original_update, :update
  def update
    mode = FreeCombatPrototype::MapMode
    if mode.active? && self.equal?(mode.session.opponent) && !(mode.session.combat.respond_to?(:npcs) && mode.session.combat.npcs)
      if !mode.session.combat.paused && [:sex, :grabber, :grabbed, :death].include?(actor.action_state)
        FreeCombatPrototype::NativeEffects.with_source(self) { update_npc }
      end
      update_animation
      update_bush_depth
      update_animation_synced
      return
    end
    fcp_original_update
  end
end

class Scene_FreeCombatMap < Scene_Map
  def start
    super
    # Attach saved continuous positions before the first native movement update.
    mode = FreeCombatPrototype::MapMode
    mode.prepare if mode.story? && FreeCombatPrototype::StorySaves.pending

  end

  def update
    super
    FreeCombatPrototype::MapMode.prepare
    mode = FreeCombatPrototype::MapMode
    update_call_menu if mode.active? && mode.session.keyboard.trigger?(:menu)
  end

  def update_call_menu
    super
  end

  def update_map_hud_input
    FreeCombatPrototype::MapMode.story? ? super : @hud.hide
  end

end
