# Fresh blank-save runtime smoke; remove after observing the title.
module ModCompatTitleProbe
  @ticks=0
  def self.tick
    @ticks+=1
    return unless @ticks==10
    checks={
      'all sixteen selected addons loaded'=>$mod_manager.load_order.count { |mod| mod.enabled && mod.loaded && mod.error.to_s.empty? }==16,
      'compatibility bridge loaded'=>defined?(FreeCombatCompatibility) && FreeCombatCompatibility.status['features'].size==6,
      'diagnostics healthy'=>FreeCombatDiagnostics.error.nil?,
      'native geometry and dispatch active'=>!LonaPerformance.error && LonaPerformance.status['native_hook'] && LonaPerformance.status['dispatch_hook'],
      'movement reads preserved WASD'=>Input::SYM_KEYS[:UP].include?(0x57) && Input::SYM_KEYS[:LEFT].include?(0x41) && Input::SYM_KEYS[:DOWN].include?(0x53) && Input::SYM_KEYS[:RIGHT].include?(0x44),
      'journal rejects non-hash context'=>LRD.current_map?(nil)==false && LRD.current_map?(false)==false,
      'journal rejects invalid map value'=>LRD.current_map?({:map_id=>false})==false
    }
    File.open('mod-title-verification.txt','w') { |f| checks.each { |name,ok| f.puts("#{ok ? 'PASS' : 'FAIL'}: #{name}") } }
    bitmap=Graphics.snap_to_bitmap
    bitmap.export('mod-title.png')
    bitmap.dispose
    exit
  rescue StandardError, ScriptError => error
    File.open('mod-title-failure.txt','w') { |f| f.puts(error.class,error.message,error.backtrace) }
    exit
  end
end
class Scene_MapTitle
  alias_method :mod_title_native_update,:update
  def update
    mod_title_native_update
    ModCompatTitleProbe.tick
  end
end
def SceneManager.first_scene_class; Scene_MapTitle; end
