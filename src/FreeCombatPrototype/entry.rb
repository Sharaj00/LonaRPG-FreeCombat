base = File.dirname(__FILE__)
load_script "#{base}/core.rb"
load_script "#{base}/scene.rb"
load_script "#{base}/map_world.rb"
if defined?(Scene_Map)
  load_script "#{base}/map_effects.rb"
  load_script "#{base}/map_combat.rb"
  load_script "#{base}/map_mode.rb"
  load_script "#{base}/map_npcs.rb"
  load_script "#{base}/story_mode.rb"
  load_script "#{base}/compatibility.rb"
  FreeCombatCompatibility.disable_legacy

  class << SceneManager
    alias_method :fcp_compatibility_original_run, :run
    def run
      FreeCombatCompatibility.install
      fcp_compatibility_original_run
    end
  end
end

# Release a previous story controller when returning to the title.
class Scene_MapTitle
  alias_method :free_combat_original_update, :update
  def update
    FreeCombatPrototype::MapMode.stop if defined?(FreeCombatPrototype::MapMode) && FreeCombatPrototype::MapMode.enabled?
    free_combat_original_update
  end
end
