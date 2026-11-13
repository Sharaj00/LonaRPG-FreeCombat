load_script 'mod_compat_acceptance.rb'
# Private full-game fixtures only. No user save is loaded by this probe.
module ModCompatProbe
  CONFIG = JSON.decode(File.read('mod-compat-config.json'))
  @lines, @keys, @frames = [], [], 0
  @phase = :new_game
  class << self
    attr_reader :keys
  end

  def self.check(name, result)
    @lines << "#{result ? 'PASS' : 'FAIL'}: #{name}"
    File.open('mod-compat-verification.txt','w') { |file| file.puts(@lines) }
    result
  end

  def self.fail(error)
    File.open('mod-compat-failure.txt','w') { |file| file.puts(error.class,error.message,error.backtrace) }
    exit
  end

  def self.boot
    expected = %w[RolePlayS _GrayRat_CustomNPCchs _LoliMama_CustomNPCchs _Milo_CustomNPCchs _Musketeer_CustomNPCchs DedGirl_chs OrkindSlayerGirl_chs LonaRpgCoockingExpanded temper_trine LonaRPG_FactionClashes LonaRPG_RestJournal PassiveStaminaRegen FreeCombatPrototype FreeCombatDiagnostics LonaPerformance]
    expected << 'FreeCombatCompatibility' if File.file?('ModScripts/_Mods/FreeCombatCompatibility/entry.rb')
    expected.each do |id|
      mod = $mod_manager.mods[id]
      check("native loader enables #{id}", !!mod && mod.enabled && mod.loaded && mod.error.to_s.empty?)
      File.open('mod-compat-loader.txt','a') { |file| file.puts([id, mod && mod.version, mod && mod.loaded, mod && mod.error].inspect) }
    end
    raise 'One or more supplied mods failed native loading' if @lines.any? { |line| line.start_with?('FAIL:') }
    check('optimization adapters installed with GC off', !LonaPerformance.error && LonaPerformance.status['native_hook'] && LonaPerformance.status['dispatch_hook'] && LonaPerformance.status['gc_batch_frames'] == 0)
    if CONFIG['phase'] == 'inspect_save'
      File.open('mod-save-shape.txt','w') do |out|
        out.puts(DataManager.method(:make_save_contents).source_location.inspect)
        File.open(DataManager.userDataPath+'FCPModCompat.rvdata2','rb') do |file|
          index=0
          until file.eof?
            begin
              object=Marshal.th_core_load(file)
              out.puts([index,file.pos,object.class,object.is_a?(Hash) ? object.keys : object.inspect[0,120]].inspect)
              index+=1
            rescue StandardError => error
              out.puts(error.class,error.message,error.backtrace)
              break
            end
          end
        end
      end
      exit
    end
    if ['cold_load','cold_maps','classify','identity','identity_route'].include?(CONFIG['phase'])
      @phase = :acceptance
      ModCompatAcceptance.cold_boot
    else
      SceneManager.goto(NewGameSewer)
    end
  rescue StandardError, ScriptError => error
    fail(error)
  end

  def self.confirm(scene)
    check('RPS creates its own default class selection', HeroClass.lona['initial'].is_a?(Array))
    scene.process_ok
    $game_player.actor.refresh
    check('RPS commits native class/history stats', !$game_player.actor.instance_variable_get(:@attribute_progress).nil? && !$game_player.actor.instance_variable_get(:@str_atk).nil?)
  rescue StandardError, ScriptError => error
    fail(error)
  end

  def self.tick(scene)
    @frames += 1
    raise 'Private compatibility fixture timed out' if @frames > 1800
    mode = FreeCombatPrototype::MapMode
    if @phase == :acceptance
      ModCompatAcceptance.tick(scene)
      return
    end
    if @phase == :new_game
      return if @frames < 8
      # Finish only the disposable fixture's introduction before selecting a test map.
      $game_map.interpreter.clear
      $game_message.clear
      $game_pause = false
      $game_player.cannot_control = false
      $story_stats['ReRollHalfEvents'] = 1
      $story_stats['TagSubTrans'] = 'StartPoint2'
      $story_stats['TagSubForceDir'] = 8
      $game_player.reserve_transfer($data_tag_maps['NoerTavern2F'].first,73,57,8)
      @phase = :arrival
      return
    end
    return unless mode.active? && !mode.session.suspended? && !$game_player.transfer?
    return if @phase != :arrival
    @phase = :checks
    if CONFIG['phase'] == 'remaining'
      @phase = :acceptance
      ModCompatAcceptance.remaining_start(scene)
      return
    end
    check('fresh modded story controller is active', mode.story? && mode.controls?($game_player))
    check('diagnostic recorder remains healthy', FreeCombatDiagnostics.error.nil?)
    player, actor, combat = $game_player, $game_player.actor, mode.session.combat
    combat.instance_variable_set(:@paused,false)
    actor.sta = actor.battle_stat.get_stat('sta',3)-20
    player.instance_variable_set(:@afk_count,0)
    before = actor.sta
    Graphics.frame_count = ((Graphics.frame_count / 60)+1)*60
    player.update
    check('passive stamina regenerates during active free combat', actor.sta == before+2)
    combat.instance_variable_set(:@paused,true)
    before = actor.sta
    Graphics.frame_count += 60
    player.update
    check('passive stamina is frozen on combat pause', actor.sta == before)
    sk = TemperTrine::STAT_KEYS
    actor.stat[sk[:stage3]] = 1
    actor.stat[sk[:stage3_frames]] = 50
    actor.temper_stage3_update!
    check('Temper frame timer is frozen on combat pause', actor.stat[sk[:stage3_frames]] == 50)
    combat.instance_variable_set(:@paused,false)
    actor.stat[sk[:stage3_frames]] = 50
    actor.temper_stage3_update!
    check('Temper frame timer resumes with combat', actor.stat[sk[:stage3_frames]] == 49)
    actor.stat[sk[:stage3]] = 0
    actor.stat[sk[:stage3_frames]] = 0
    extra_checks
    if CONFIG['phase'] == 'full'
      @phase = :acceptance
      ModCompatAcceptance.start(scene)
      return
    end
    File.open('mod-compat-complete.txt','w') { |file| file.puts("COMPLETE: #{@lines.count { |line| line.start_with?('PASS:') }} passed, #{@lines.count { |line| line.start_with?('FAIL:') }} failed") }
    exit
  rescue StandardError, ScriptError => error
    fail(error)
  end
  def self.extra_checks
    mode = FreeCombatPrototype::MapMode
    session, actor = mode.session, $game_player.actor
    keyboard = session.keyboard
    @action_observations = []
    singleton = class << FCL; self; end
    singleton.send(:alias_method, :mod_probe_action_key, :action_key_pressed?)
    singleton.send(:define_method, :action_key_pressed?) do
      value = mod_probe_action_key
      ModCompatProbe.observe_action(value)
      value
    end
    begin
      [[:interact,0x45],[:enter,0x0D]].each do |name,code|
        @keys = []; keyboard.update
        @keys = [code]; keyboard.update
        @action_observations = []
        $game_player.check_action_event(true)
        check("Faction Clashes accepts explicit #{name}", @action_observations.include?(true))
        $game_map.interpreter.clear; $game_message.clear
      end
      @keys = [0x43]; keyboard.update
      @forced_native_action = true
      @action_observations = []
      $game_player.start_map_event($game_player.x,$game_player.y,[0],false,true)
      check('Faction Clashes rejects attack/touch as reward intent', !@action_observations.empty? && !@action_observations.include?(true))
    ensure
      @keys = []; keyboard.update
      @forced_native_action = false
      singleton.send(:alias_method, :action_key_pressed?, :mod_probe_action_key)
      singleton.send(:remove_method, :mod_probe_action_key)
    end
    old_ctx, old_story = LRD.ctx, $story_stats
    old_class = HeroClass.lona
    contents = DataManager.make_save_contents
    replacement = old_story.dup
    replacement[LRD::STORE] = LRD.store.dup
    replacement[LRD::STORE]['visit'] = {:key=>'compat-abandoned',:class=>:safe}
    contents[:story] = replacement
    contents[:hero_class_lona] = HeroClass.lona.merge('compat_failed_load'=>true)
    marker = RuntimeError.new('private abandoned load')
    begin
      FreeCombatPrototype::StorySaves.load_transaction do
        DataManager.extract_save_contents(contents)
        raise marker
      end
    rescue RuntimeError => error
      raise unless error.equal?(marker)
    end
    check('failed load restores native story identity', $story_stats.equal?(old_story))
    check('failed load restores Rest Journal visit identity', LRD.ctx.equal?(old_ctx))
    check('failed load restores RolePlay-S class identity',HeroClass.lona.equal?(old_class))
    HeroClass.lona = old_class
    LRD.ctx_set(old_ctx)
    lane = session.world.geometry.cells.find do |x,y|
      $game_map.passable?(x,y,4) && $game_map.passable?(x-1,y,6) &&
        (x-$game_player.x).abs+(y-$game_player.y).abs>5 &&
        $game_map.events.values.none? { |event| !event.deleted? && (event.real_x-x).abs<2 && (event.real_y-y).abs<2 }
    end
    raise 'No private dodge lane' unless lane
    ids = $game_map.events.keys
    $game_map.summon_event('CompMusketeer',*lane)
    event = $game_map.events[($game_map.events.keys-ids).first]
    raise 'Native Musketeer fixture did not spawn' unless event && event.actor
    session.combat.npcs.refresh
    check('modified Musketeer registers as a native controlled NPC',session.combat.npcs.registered?(event))
    session.world.refresh_event_walls($game_map.events.values.reject { |e| session.combat.npcs.registered?(e) },nil)
    event.set_direction(6)
    token = session.combat.npcs.body(event)
    before = token.x
    FreeCombatPrototype::NativeEffects.with_source(event) { event.jump_low_alt(-1,0) }
    session.combat.npcs.tick(event)
    check('RolePlay-S backward dodge moves controlled NPC body',token.x < before-1)
    check('RolePlay-S backward dodge preserves facing',event.direction==6)
    event.delete
    session.combat.npcs.refresh
    check('modified NPC deletion releases its controller',!session.combat.npcs.registered?(event))
  end

  def self.advance_dialog?
    [:new_game,:arrival,:acceptance].include?(@phase) && $game_message && ($game_message.busy? || $game_message.visible) && Graphics.frame_count % 10 == 0
  end

  def self.finish
    File.open('mod-compat-complete.txt','w') { |file| file.puts("COMPLETE: #{@lines.count { |line| line.start_with?('PASS:') }} passed, #{@lines.count { |line| line.start_with?('FAIL:') }} failed") }
    exit
  end

  def self.observe_action(value); @action_observations << value; end
  def self.forced_native_action?; @forced_native_action == true; end

end

class Scene_ModCompatBoot < Scene_Base
  def update; ModCompatProbe.boot; end
end
def SceneManager.first_scene_class; Scene_ModCompatBoot; end

class Character_Creation
  def update
    return if @mod_compat_confirmed
    @mod_compat_confirmed = true
    ModCompatProbe.confirm(self)
  end
end

class FreeCombatPrototype::Keyboard
  def held?(code); ModCompatProbe.keys.include?(code); end
  def focused?; true; end
end

class Scene_FreeCombatMap
  alias_method :mod_compat_probe_update, :update
  def update
    mod_compat_probe_update
    ModCompatProbe.tick(self)
  rescue StandardError, ScriptError => error
    ModCompatProbe.fail(error)
  end
end

class << Input
  alias_method :mod_probe_native_trigger, :trigger?
  def trigger?(key)
    return true if key == :C && (ModCompatProbe.forced_native_action? || ModCompatProbe.advance_dialog?)
    mod_probe_native_trigger(key)
  end
end
