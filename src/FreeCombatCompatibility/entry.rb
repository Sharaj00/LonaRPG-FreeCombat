# RGSS301 / Ruby 1.9.2. Original third-party scripts remain in their own addons.
module FreeCombatCompatibility
  VERSION = '0.1.1'
  @features = []

  def self.enabled?(id)
    mod = $mod_manager.mods[id]
    mod && mod.enabled && mod.loaded && mod.error.to_s.empty?
  end

  def self.status
    {'version'=>VERSION, 'features'=>@features.dup}
  end

  def self.feature(name)
    @features << name
  end

  def self.paused_actor?(actor)
    $game_player && actor.equal?($game_player.actor) && FreeCombatPrototype::MapMode.paused?
  end

  def self.guard_temper_tick(name)
    original = Game_Actor.instance_method(name)
    Game_Actor.send(:define_method, name) do
      original.bind(self).call unless FreeCombatCompatibility.paused_actor?(self)
    end
  end

  def self.recover_stamina(player)
    frame = Graphics.frame_count
    return unless player.equal?($game_player) && player.actor && frame % 60 == 0
    return if FreeCombatPrototype::MapMode.paused?
    return if @regen_player.equal?(player) && @regen_frame == frame
    @regen_player, @regen_frame = player, frame
    actor = player.actor
    actor.sta = actor.sta + 2 if actor.sta < actor.battle_stat.get_stat('sta', 3)
  end

  def self.interacting?
    @interacting == true
  end

  def self.with_interaction
    previous, @interacting = @interacting, true
    yield
  ensure
    @interacting = previous
  end

  def self.load_context
    state = {}
    state[:visit] = LRD.ctx if enabled?('LonaRPG_RestJournal')
    state[:hero_class] = HeroClass.lona if enabled?('RolePlayS')
    state
  end

  def self.restore_load_context(state)
    LRD.ctx_set(state[:visit]) if state.has_key?(:visit)
    HeroClass.lona = state[:hero_class] if state.has_key?(:hero_class)
  end

  def self.extra_map_info(value)
    value.is_a?(String) && $data_mapinfos && $data_mapinfos[value]
  end

  def self.same_map?(left, right)
    return false if left.nil? || right.nil?
    return false unless left.respond_to?(:to_i) && right.respond_to?(:to_i)
    left_info, right_info = extra_map_info(left), extra_map_info(right)
    (left_info ? left_info.id : left.to_i) == (right_info ? right_info.id : right.to_i)
  end
end

if FreeCombatCompatibility.enabled?('PassiveStaminaRegen')
  # Remove only the captured passive wrapper, preserving every earlier native/mod hook.
  location = Game_Player.instance_method(:fcp_original_update).source_location
  unless location && location[0].gsub('\\','/').end_with?('/PassiveStaminaRegen/PassiveStaminaRegen.rb')
    raise 'Load PassiveStaminaRegen immediately before FreeCombatPrototype, then FreeCombatCompatibility'
  end
  class Game_Player
    alias_method :fcp_original_update, :passive_sta_regen_update
    alias_method :fcc_player_update, :update
    def update
      result = fcc_player_update
      FreeCombatCompatibility.recover_stamina(self)
      result
    end
  end
  FreeCombatCompatibility.feature('passive_stamina')
end

if FreeCombatCompatibility.enabled?('temper_trine')
  # Date-based rest/decay and dialog-pause release keep their native behavior.
  [:temper_stage3_update!, :temper_stage2_update!, :temper_desire_activity_tick!].each do |name|
    FreeCombatCompatibility.guard_temper_tick(name)
  end
  FreeCombatCompatibility.feature('temper_frame_pause')
end

if FreeCombatCompatibility.enabled?('LonaRPG_FactionClashes')
  class Game_Player
    alias_method :fcc_check_action_event, :check_action_event
    def check_action_event(*args)
      mode = FreeCombatPrototype::MapMode
      explicit = args[0] == true && mode.active? &&
        (mode.session.keyboard.trigger?(:interact) || mode.session.keyboard.trigger?(:enter))
      return fcc_check_action_event(*args) unless explicit
      FreeCombatCompatibility.with_interaction { fcc_check_action_event(*args) }
    end
  end
  class << FCL
    alias_method :fcc_action_key_pressed, :action_key_pressed?
    def action_key_pressed?
      return fcc_action_key_pressed unless FreeCombatPrototype::MapMode.active?
      return fcc_action_key_pressed if cfg(['reward_fork','require_action_key'], true) != true
      FreeCombatCompatibility.interacting?
    end
  end
  FreeCombatCompatibility.feature('faction_interaction_intent')
end

if FreeCombatCompatibility.enabled?('LonaRPG_RestJournal') || FreeCombatCompatibility.enabled?('RolePlayS')
  class << FreeCombatPrototype::StorySaves
    alias_method :fcc_load_transaction, :load_transaction
    def load_transaction
      previous = FreeCombatCompatibility.load_context
      result = fcc_load_transaction { yield }
      FreeCombatCompatibility.restore_load_context(previous) unless result
      result
    rescue Exception
      FreeCombatCompatibility.restore_load_context(previous) if previous
      raise
    end
  end
  FreeCombatCompatibility.feature('external_load_rollback')
end

if FreeCombatCompatibility.enabled?('RolePlayS')
  class Game_Character
    alias_method :fcc_jump_low_alt, :jump_low_alt
    def jump_low_alt(dx, dy, peak = 5)
      unless FreeCombatPrototype::MapMode.controls?(self) && FreeCombatPrototype::NativeEffects.source
        return fcc_jump_low_alt(dx, dy, peak)
      end
      jump(dx, dy, peak)
    end
  end
  FreeCombatCompatibility.feature('roleplay_backward_dodge')
end

if FreeCombatCompatibility.enabled?('LonaRPG_RestJournal') && FreeCombatCompatibility.enabled?('RolePlayS')
  class << LRD
    alias_method :fcc_note_data, :note_data
    def note_data(map_id = nil)
      info = FreeCombatCompatibility.extra_map_info(map_id)
      return fcc_note_data(map_id) unless info
      if $game_map && $game_map.map_id == info.id
        current = $game_map.instance_variable_get(:@map)
        return Note.get_data(current.note.to_s) if current
      end
      @fcc_extra_notes ||= {}
      return @fcc_extra_notes[map_id] if @fcc_extra_notes.has_key?(map_id)
      registered = load_data(info.filename)
      @fcc_extra_notes[map_id] = Note.get_data(registered.note.to_s)
    rescue StandardError => failure
      error('compatibility_extra_map_note', failure)
      {}
    end

    alias_method :fcc_current_map, :current_map?
    def current_map?(visit = ctx)
      return fcc_current_map(visit) unless visit.is_a?(Hash)
      wanted = visit[:map_id]
      current = $game_map && ($game_map.map_id_rec || $game_map.map_id)
      unless FreeCombatCompatibility.extra_map_info(wanted) || FreeCombatCompatibility.extra_map_info(current)
        return fcc_current_map(visit)
      end
      FreeCombatCompatibility.same_map?(wanted, current)
    end

    alias_method :fcc_describe, :describe
    def describe(map_id, from_overmap = nil)
      description = fcc_describe(map_id, from_overmap)
      if visit_open? && (FreeCombatCompatibility.extra_map_info(map_id) || FreeCombatCompatibility.extra_map_info(ctx[:map_id]))
        fresh_key = key_for(map_id, nil, from_overmap)
        description['key'] = if fresh_key && FreeCombatCompatibility.same_map?(ctx[:map_id], map_id)
          ctx[:key] || fresh_key
        else
          fresh_key
        end
      end
      description
    end
  end
  FreeCombatCompatibility.feature('rest_journal_extra_maps')
end
