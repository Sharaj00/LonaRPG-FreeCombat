# RGSS3 / Ruby 1.9.2. Disposable test tools; never loaded by Free Combat alone.
module FreeCombatPrototype
  module MapMode
    class << self
      attr_accessor :kit_prepared
    end
    def self.test?
      enabled? && !story?
    end

    def self.launch
      stop
      @enabled = true
      @story = false
      @session = nil
      @kit_prepared = false
      @paused = true
      DataManager.fcp_story_setup_new_game(false)
      $story_stats['TagSubTrans'] = 'StartPoint2'
      $story_stats['TagSubForceDir'] = 8
      $game_map.setup($data_tag_maps['NoerTavern2F'].first)
      @target_map_id = $game_map.map_id
      $game_player.moveto(73, 57)
      $game_player.force_update = true
      $game_player.transparent = false
      $game_system.menu_disabled = false
      SceneManager.goto(Scene_FreeCombatMap)
    end

  end

  class NativeCombat
    def stats(actor)
      "HP=#{actor.health} STA=#{actor.sta} state=#{actor.action_state}"
    end

    alias_method :fcd_test_initialize, :initialize
    def initialize(world, opponent)
      fcd_test_initialize(world, opponent)
      return unless MapMode.test?
      @issued_items = @player.instance_variable_get(:@fcp_issued_items) || []
      @player.instance_variable_set(:@fcp_issued_items, @issued_items)
      unless MapMode.kit_prepared
        ['WeaponryKnowledge', 'ManaKnowledge', 'NunKnowledge'].each { |name| @player.add_state(name) }
        @player.refresh
        $data_skills.compact.each do |skill|
          native = $data_arpgskills[skill.type_tag]
          next unless native
          next unless [native.summon_user, native.summon_hit, native.summon_hold].compact.all? { |name| $data_EventLib[name] }
          @player.learn_skill(skill.id) if skill.item_name.start_with?('Basic')
        end
        equip('ItemMhShortSword')
        MapMode.kit_prepared = true
      end
    end

    def equip(name, slot = 'MH')
      return unless can_launch?(@player)
      item = $data_ItemName[name]
      slots = @player.report_reverse_equippable(item)
      unless slots
        @notice = 'Equipment blocked by native requirements'
        return
      end
      (slots + @player.report_reverse_unequip_by(item)).uniq.each { |slot| @player.change_equip(slot, nil) }
      unless @player.equips.include?(item) || $game_party.item_number(item) > 0
        $game_party.gain_item(item, 1)
        @issued_items << item
      end
      @player.change_equip(slot, item)
      unless @player.equips.include?(item)
        @notice = 'Weapon requirements not met'
        return
      end
      @issued_items.delete_if do |issued|
        next false if @player.equips.include?(issued)
        $game_party.lose_item(issued, 1) if $game_party.item_number(issued) > 0
        true
      end
      $game_player.move_normal
      @notice = "Equipped: #{weapon_name}"
    end

    def weapon_name
      weapon = @player.equips.compact.find { |item| item.is_a?(RPG::Weapon) }
      weapon ? $game_text[weapon.name] : 'Unarmed'
    end

    def skill_names
      skills = @player.usable_skills
      ['normal', 'heavy', 'control'].map do |type|
        skill = skills.find { |entry| entry.type == type }
        skill ? skill.type_tag : '-'
      end.join(' / ')
    end

    def cycle_equipment(slot)
      return unless can_launch?(@player)
      type = $data_system.equip_type_name[slot]
      catalog = ($data_weapons + $data_armors).compact.select do |item|
        item.etype_id == type && !item.added_skills.empty? &&
          (item.wtype_id ? @player.equip_wtype_ok?(item.wtype_id) : @player.equip_atype_ok?(item.atype_id))
      end
      current = @player.equips[type]
      index = catalog.index(current) || -1
      equip(catalog[(index + 1) % catalog.size].item_name, slot) unless catalog.empty?
    end

    alias_method :fcd_test_update, :update
    def update(dx, dy, keyboard)
      if MapMode.test? && keyboard.trigger?(:weapon)
        bow = @player.equips.include?($data_ItemName['Item2MhLongBow'])
        equip(bow ? 'ItemMhShortSword' : 'Item2MhLongBow')
      end
      cycle_equipment('MH') if MapMode.test? && keyboard.trigger?(:mainhand)
      cycle_equipment('SH') if MapMode.test? && keyboard.trigger?(:offhand)
      fcd_test_update(dx, dy, keyboard)
    end
  end
end

class << DataManager
  [:save_game_without_rescue, :save_doom_without_header, :save_custom_without_header, :make_save_screenshot, :saveFileDeleteDoom].each do |name|
    original = ('fcp_original_' + name.to_s).to_sym
    alias_method original, name
    define_method(name) do |*args|
      return false if FreeCombatPrototype::MapMode.test?
      send(original, *args)
    end
  end
  [:load_game, :load_game_without_rescue, :load_doom_without_rescue, :load_custom_without_rescue, :delete_save_file, :doAutoSave].each do |name|
    next unless method_defined?(name)
    original = ('fcp_original_' + name.to_s).to_sym
    alias_method original, name
    define_method(name) do |*args|
      return false if FreeCombatPrototype::MapMode.test?
      send(original, *args)
    end
  end
end

class Scene_MapTitle
  alias_method :fcd_title_update, :update
  def update
    FreeCombatPrototype::MapMode.stop if FreeCombatPrototype::MapMode.enabled?
    if Input.trigger?(:F7) && defined?(FreeCombatPrototype::MapMode)
      FreeCombatPrototype::MapMode.launch
      return
    end
    if Input.trigger?(:F6)
      FreeCombatPrototype::Arena.new.run
      return
    end
    fcd_title_update
  end
end

class Scene_FreeCombatMap
  alias_method :fcd_test_scene_update, :update
  def update
    if Input.trigger?(:F8) && FreeCombatPrototype::MapMode.test?
      FreeCombatPrototype::MapMode.stop
      $titleCreateActorReq = true
      SceneManager.goto(Scene_Title)
      return
    end
    fcd_test_scene_update
  end
end
