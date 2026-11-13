# RGSS3 / Ruby 1.9. Story saves retain native data, never live controller objects.
module FreeCombatPrototype
  module StorySaves
    class << self
      attr_accessor :pending
    end

    def self.capture
      session = MapMode.session
      unless session
        return {:version=>3, :map_id=>$game_map.map_id, :paused=>MapMode.pause_state,
          :travel_recovery=>MapMode.travel_recovery, :projectiles=>[], :recovery=>[], :facing=>nil}
      end
      combat, world = session.combat, session.world
      projectiles = combat.effects.instance_variable_get(:@projectiles).map do |id, shot|
        [id, shot.dx, shot.dy, shot.life, combat.effects.instance_variable_get(:@miles)[id], shot.x, shot.y]
      end
      recovery = combat.recovery.instance_variable_get(:@actions).values.map do |actor, frames|
        [actor.map_token.equal?($game_player) ? 0 : actor.map_token.id, frames]
      end
      held_key = combat.instance_variable_get(:@held)[$game_player.actor]
      {:version => 3, :map_id => $game_map.map_id, :paused=>combat.paused, :held_key=>held_key, :projectiles => projectiles,
       :recovery => recovery, :facing => [world.player.facing_x, world.player.facing_y]}
    end

    def self.resume_controller
      session = MapMode.session
      return unless session
      combat = session.combat
      combat.npcs.refresh
      $game_map.events.values.each do |event|
        data = event.summon_data
        next unless data && !event.deleted? && combat.effects.owns?(data[:user] || data[:fcp_owner])
        event.instance_variable_set(:@fcp_native_anchor_handled, true)
        direction = event.direction
        combat.effects.register(event, data)
        event.set_direction(direction)
      end
      data, self.pending = pending, nil
      return unless data.is_a?(Hash) && [1,2,3].include?(data[:version]) && data[:map_id] == $game_map.map_id
      session.world.player.facing_x, session.world.player.facing_y = data[:facing] if data[:facing]
      data[:projectiles].each do |id, dx, dy, life, miles, x, y|
        shot = combat.effects.instance_variable_get(:@projectiles)[id]
        next unless shot
        shot.dx, shot.dy, shot.life = dx, dy, life
        if x && y
          shot.x, shot.y = x, y
          combat.effects.sync($game_map.events[id], shot)
        end
        combat.effects.instance_variable_get(:@miles)[id] = miles
      end
      data[:recovery].each do |id, frames|
        event = id == 0 ? $game_player : $game_map.events[id]
        next unless event && event.actor
        actor = event.actor
        combat.recovery.instance_variable_get(:@actions)[actor.object_id] = [actor, frames]
      end
      actor = $game_player.actor
      if actor.skill && actor.skill.holding?
        key = data[:held_key]
        if Keyboard::KEYS.has_key?(key)
          combat.instance_variable_get(:@held)[actor] = key
        elsif data[:version] < 3 && $game_player.instance_variable_get(:@holding_key).nil?
          # Older custom-key saves cannot resume a hold with no release input.
          actor.cancel_holding(false)
        end
      end
    end

    def self.with_native_data
      bindings = []
      [Game_Battler, Game_CharacterBase].each do |klass|
        ObjectSpace.each_object(klass) do |object|
          [:@fcp_combat, :@fcp_effects].each do |name|
            next unless object.instance_variable_defined?(name)
            value = object.send(:remove_instance_variable, name)
            bindings << [object, name, value]
          end
        end
      end
      yield
    ensure
      bindings.each { |object, name, value| object.instance_variable_set(name, value) }
    end

    # Keep native object identities intact until a load has actually succeeded.
    def self.load_transaction
      globals = [$story_stats,$game_date,$game_temp,$game_system,$game_timer,$game_message,
        $game_switches,$game_variables,$game_self_switches,$game_actors,$game_NPCLayerMain,
        $game_NPCLayerSub,$game_portraits,$game_party,$game_map,$game_player,$dialog_timer,
        $game_text,$mail_text,$game_boxes,$game_pause,$hudForceHide,$balloonForceHide,$cg,$bg]
      old_pending, old_index = pending, DataManager.instance_variable_get(:@last_savefile_index)
      portraits = $game_portraits ? %w[Lona NPCLayerMain NPCLayerSub].map do |name|
        portrait = $game_portraits.getPortrait(name)
        [portrait, portrait.base_char]
      end : []
      result = yield
      if result
        MapMode.release(false)
        return result
      end
      restore_globals(globals, portraits)
      self.pending = old_pending
      DataManager.instance_variable_set(:@last_savefile_index, old_index)
      result
    rescue Exception
      restore_globals(globals, portraits)
      self.pending = old_pending
      DataManager.instance_variable_set(:@last_savefile_index, old_index)
      raise
    end

    def self.restore_globals(values, portraits)
      $story_stats,$game_date,$game_temp,$game_system,$game_timer,$game_message,
        $game_switches,$game_variables,$game_self_switches,$game_actors,$game_NPCLayerMain,
        $game_NPCLayerSub,$game_portraits,$game_party,$game_map,$game_player,$dialog_timer,
        $game_text,$mail_text,$game_boxes,$game_pause,$hudForceHide,$balloonForceHide,$cg,$bg = values
      (portraits || []).each { |portrait, actor| portrait.base_char = actor }
    end

    def self.write(paths)
      return yield unless MapMode.story?
      if @writing
        begin
          return yield
        rescue Exception
          @failed = true
          raise
        end
      end
      @writing, @failed = true, false
      snapshots = []
      begin
        paths.each do |path|
          data = File.file?(path) ? File.open(path, 'rb') { |f| f.read } : nil
          File.open(path + '.free-combat.bak', 'wb') { |f| f.write(data) } if data
          snapshots << [path, data]
        end
        result = with_native_data { yield }
        restore(snapshots) if @failed || result == false
        result
      rescue Exception
        restore(snapshots)
        raise
      ensure
        @writing, @failed = false, false
      end
    end

    def self.writing?
      @writing == true
    end

    def self.restore(snapshots)
      snapshots.each do |path, data|
        if data
          File.open(path, 'wb') { |f| f.write(data) }
        elsif File.file?(path)
          File.delete(path)
        end
      end
    end
  end
end

class << DataManager
  alias_method :fcp_story_delete_doom, :saveFileDeleteDoom
  def saveFileDeleteDoom
    result = fcp_story_delete_doom
    unless FreeCombatPrototype::StorySaves.writing?
      backup = make_filenameDoom + '.free-combat.bak'
      File.delete(backup) if File.file?(backup)
    end
    result
  end

  alias_method :fcp_story_setup_new_game, :setup_new_game
  def setup_new_game(*args)
    FreeCombatPrototype::MapMode.stop
    FreeCombatPrototype::StorySaves.pending = nil
    result = fcp_story_setup_new_game(*args)
    FreeCombatPrototype::MapMode.start_story
    result
  end

  alias_method :fcp_story_make_save_contents, :make_save_contents
  def make_save_contents
    contents = fcp_story_make_save_contents
    contents[:free_combat_story] = FreeCombatPrototype::StorySaves.capture if FreeCombatPrototype::MapMode.story?
    contents
  end

  alias_method :fcp_story_extract_save_contents, :extract_save_contents
  def extract_save_contents(contents)
    result = fcp_story_extract_save_contents(contents)
    FreeCombatPrototype::StorySaves.pending = contents[:free_combat_story]
    result
  end

  [:load_game_without_rescue, :load_doom_without_rescue, :load_custom_without_rescue].each do |name|
    next unless method_defined?(name)
    original = ('fcp_story_' + name.to_s).to_sym
    alias_method original, name
    define_method(name) do |*args|
      result = FreeCombatPrototype::StorySaves.load_transaction { send(original, *args) }
      FreeCombatPrototype::MapMode.start_story if result
      result
    end
  end

  [:save_game, :save_game_without_rescue, :doomModeSave, :save_doom_without_header, :save_custom_without_header].each do |name|
    next unless method_defined?(name)
    original = ('fcp_story_' + name.to_s).to_sym
    alias_method original, name
    define_method(name) do |*args|
      paths = if name == :save_custom_without_header
        [userDataPath + args[0].to_s + '.rvdata2']
      elsif [:doomModeSave, :save_doom_without_header].include?(name)
        [make_filenameDoom]
      else
        [make_filename(args[0]), make_filename_screenshot(args[0])]
      end
      FreeCombatPrototype::StorySaves.write(paths) { send(original, *args) }
    end
  end
end
