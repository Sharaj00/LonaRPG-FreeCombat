# Private native runner only. Reuse the established independent fixture helpers.
load_script 'integrated-probe-helpers.rb'
module ModCompatProbe
  INTEGRATED_CONFIG = JSON.decode(File.read('integrated-config.json'))

  def self.boot
    config = INTEGRATED_CONFIG
    check('compatibility belongs to core', FreeCombatCompatibility::BUILT_IN)
    check('selected adapters installed', FreeCombatCompatibility.status['features'].sort == config['features'].sort)
    check('adapter skip report matches case', FreeCombatCompatibility.status['skipped'].keys.sort == (config['skipped'] || []).sort)
    before = Game_Player.instance_method(:update)
    FreeCombatCompatibility.install
    check('second installation does not alias methods again', Game_Player.instance_method(:update) == before)
    config['enabled'].each do |id|
      mod=$mod_manager.mods[id]
      check('native addon loaded: '+id, mod && mod.loaded && mod.enabled && mod.error.empty?)
    end
    (config['versions'] || {}).each do |id, version|
      check('release version loaded: '+id, $mod_manager.mods[id].version.to_s == version)
    end
    if config['versions']
      check('built-in compatibility matches release', FreeCombatCompatibility::VERSION == config['versions']['FreeCombatPrototype'])
    end
    legacy = $mod_manager.mods['FreeCombatCompatibility']
    if config['legacy']
      check('obsolete standalone never executes', legacy && !legacy.loaded && !legacy.enabled && !legacy.error.to_s.empty?)
    else
      check('standalone addon physically absent', legacy.nil?)
    end
    check('Diagnostics remains healthy', FreeCombatDiagnostics.error.nil?)
    check('performance hooks remain active', LonaPerformance.status['native_hook'] && LonaPerformance.status['dispatch_hook'] && !LonaPerformance.error)
    @lines << 'STATUS: '+FreeCombatDiagnostics.json(FreeCombatCompatibility.status)
    if config['gameplay']
      check('independent native combined save loads', DataManager.load_custom_without_rescue('SavQuick') == true)
      $game_system.on_after_load
      @phase = :acceptance
      SceneManager.goto(Scene_Map)
    else
      finish
    end
  rescue StandardError, ScriptError => error
    fail(error)
  end

  def self.tick(scene)
    mode=FreeCombatPrototype::MapMode
    return unless mode.active? && !mode.session.suspended?
    if @integrated_reload
      check('real quick load restores saved marker', $game_variables[995] == 81112)
      check('journal context survives quick load', LRD.ctx.is_a?(Hash))
      check('class context survives quick load', HeroClass.lona['initial']==@integrated_class)
      finish
    end
    return if @integrated_done
    @integrated_done=true
    actor,combat=$game_player.actor,mode.session.combat
    check('controller owns native player',mode.controls?($game_player))
    combat.instance_variable_set(:@paused,false)
    actor.sta=actor.battle_stat.get_stat('sta',3)-20
    $game_player.instance_variable_set(:@afk_count,0)
    Graphics.frame_count=((Graphics.frame_count/60)+1)*60
    before=actor.sta
    $game_player.update
    check('integrated passive regeneration ticks once',actor.sta==before+2)
    $game_player.update
    check('second player update cannot double regeneration',actor.sta==before+2)
    combat.instance_variable_set(:@paused,true)
    Graphics.frame_count+=60
    $game_player.update
    check('integrated regeneration respects pause',actor.sta==before+2)
    sk=TemperTrine::STAT_KEYS
    actor.stat[sk[:stage3]]=1
    actor.stat[sk[:stage3_frames]]=50
    actor.temper_stage3_update!
    check('integrated Temper respects pause',actor.stat[sk[:stage3_frames]]==50)
    combat.instance_variable_set(:@paused,false)
    actor.temper_stage3_update!
    check('integrated Temper resumes',actor.stat[sk[:stage3_frames]]==49)
    actor.stat[sk[:stage3]]=0
    extra_checks
    first=$mod_manager.get_resource('RolePlayS','r1_PlainField4.rvdata2')
    second=$mod_manager.get_resource('RolePlayS','r4_RainFroest4.rvdata2')
    check('integrated journal resolves extra map notes',LRD.note_data(first)['region'].to_s=='1')
    check('registered maps keep separate canonical identities',!FreeCombatCompatibility.same_map?(first,second))
    $game_variables[995]=81112
    @integrated_class=HeroClass.lona['initial'].dup
    scene.quickSave
    check('real scene quick save writes native save',File.file?(DataManager.userDataPath+'SavQuick.rvdata2'))
    $game_variables[995]=0
    @integrated_reload=true
    scene.quickLoad
  rescue StandardError, ScriptError => error
    fail(error)
  end
end

# Inject only the metadata/interface mismatch, before the production install hook.
if ModCompatProbe::INTEGRATED_CONFIG['unsupported']
  $mod_manager.mods['temper_trine'].version='9.9.9'
end
if ModCompatProbe::INTEGRATED_CONFIG['missing_interface']
  Game_Actor.send(:remove_method,:temper_stage2_update!)
end
