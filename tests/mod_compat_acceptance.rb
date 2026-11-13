# Extra native integration cases; invoked only in the private compatibility copy.
module ModCompatAcceptance
  def self.check(name, value); ModCompatProbe.check(name,value); end

  def self.spawn(name, offset = 0)
    world = FreeCombatPrototype::MapMode.session.world
    cell = world.geometry.cells.find do |x,y|
      x > 2 && $game_map.passable?(x,y,4) &&
        (x-$game_player.x).abs+(y-$game_player.y).abs > 5+offset &&
        $game_map.events.values.none? { |event| !event.deleted? && (event.real_x-x).abs<2 && (event.real_y-y).abs<2 }
    end
    raise 'No native fixture cell' unless cell
    ids = $game_map.events.keys
    if name == 'UniqueGrayRat'
      $game_player.record_companion_name_front = name
      $game_player.record_companion_front_date = nil
    end
    data = name == 'UniqueGrayRat' ? {:followerFRONT=>true} : nil
    $game_map.summon_event(name,cell[0],cell[1],-1,data)
    event = $game_map.events[($game_map.events.keys-ids).first]
    unless event && event.actor
      return nil if name != 'CompMusketeer'
      raise "Native template #{name} did not spawn"
    end
    FreeCombatPrototype::MapMode.session.combat.npcs.refresh
    event
  end

  def self.start(scene)
    mode, actor = FreeCombatPrototype::MapMode, $game_player.actor
    combat = mode.session.combat
    check('compatibility addon enables every verified bridge', FreeCombatCompatibility.status['features'].size >= 5)
    sk = TemperTrine::STAT_KEYS
    combat.instance_variable_set(:@paused,true)
    actor.stat[sk[:s2_mast_frames]] = 30
    actor.temper_stage2_update!
    check('Temper Stage2 counter freezes on combat pause',actor.stat[sk[:s2_mast_frames]]==30)
    combat.instance_variable_set(:@paused,false)
    actor.temper_stage2_update!
    check('Temper Stage2 counter resumes',actor.stat[sk[:s2_mast_frames]]==29)
    actor.stat[sk[:s2_mast_frames]]=0
    $game_message.clear
    $game_pause=false
    combat.instance_variable_set(:@paused,true)
    TemperTrineHooks.begin_dialog_pause!
    TemperTrineHooks.tick_dialog_pause!
    check('Temper dialog pause still releases while combat is paused',!$game_pause && !TemperTrineHooks.dialog_paused?)
    state=$data_StateName[CookingExpandedMod::REGEN_STATE]
    check('Cooking items and both regeneration states load',CookingExpandedMod::ITEMS.all? { |row| $data_ItemName[row[0]] } && state && $data_StateName['CexpRegenLegend'])
    actor.add_state(state.id)
    actor.health=actor.battle_stat.get_stat('health',ActorStat::MAX_STAT)-15
    CookingExpandedMod.instance_variable_set(:@regen_frames,CookingExpandedMod::REGEN_SECONDS*60-1)
    hp=actor.health
    actor.update_state_frames
    check('Cooking regeneration freezes on combat pause',actor.health==hp)
    combat.instance_variable_set(:@paused,false)
    actor.update_state_frames
    check('Cooking regeneration resumes through the native actor hook',actor.health>hp)
    actor.remove_state(state.id)
    cursed=$data_StateName[CookingExpandedMod::DIE_STATE]
    actor.add_state(cursed.id)
    CookingExpandedMod.die_soon_start
    check('Cooking delayed-effect timer is recorded', $story_stats[CookingExpandedMod::DIE_KEY].to_i > $game_date.dateAmt)
    CookingExpandedMod.cure_die_soon(actor)
    check('Cooking cure cancels its state and timer',actor.state_stack(cursed.id)==0 && $story_stats[CookingExpandedMod::DIE_KEY]==0)
    combat.instance_variable_set(:@paused,true)
    %w[UniqueGrayRat UniqueMilo UniqueBossMamaT1 CompMusketeer].each_with_index do |name,index|
      check("custom NPC data loads: #{name}",!!$data_npcs[name])
      event=spawn(name,index)
      unless event
        File.open('mod-compat-limits.txt','a') { |f| f.puts("#{name}: native plot/ownership template requires story setup; runtime appearance remains manual") }
        $game_player.record_companion_name_front=nil if name=='UniqueGrayRat'
        next
      end
      check("custom NPC registers continuously: #{name}",combat.npcs.registered?(event))
      scene.instance_variable_get(:@spriteset).update
      check("custom NPC renders without a missing-resource error: #{name}",!event.deleted?)
      event.delete
      $game_player.record_companion_name_front = nil if name == 'UniqueGrayRat'
      combat.npcs.refresh
      check("custom NPC deletion is safe: #{name}",!combat.npcs.registered?(event))
    end
    actor.add_attribute_exp(:str,0.25)
    check('RolePlay-S attribute progression survives continuous control',actor.attribute_progress(:str)[:exp]>=0.25)
    event=spawn('CompMusketeer')
    event.set_this_event_companion_front('CompMusketeer',true,nil)
    check('native companion recruitment remains compatible',event.actor.master.equal?($game_player) && event.follower[0]==1)
    $game_map.show_status_bars(event)
    check('RolePlay-S NPC status bar exists before saving',!$game_map.status_bars.empty?)
    $game_variables[995]=71014
    actor.stat[sk[:stage3_frames]]=314
    @class_saved=HeroClass.lona['initial'].dup
    scene.quickSave
    check('RolePlay-S quick save succeeds with an active status bar',File.file?(DataManager.userDataPath+'SavQuick.rvdata2'))
    check('save funnel clears transient status bars', $game_map.status_bars.empty?)
    $game_variables[995]=0
    @phase=:reload
    @ticks=0
    scene.quickLoad
  end

  def self.remaining_start(scene)
    mode, actor = FreeCombatPrototype::MapMode, $game_player.actor
    combat = mode.session.combat
    combat.instance_variable_set(:@paused,true)
    sk = TemperTrine::STAT_KEYS
    actor.add_attribute_exp(:str,0.25)
    check('RolePlay-S attribute progression survives continuous control',actor.attribute_progress(:str)[:exp]>=0.25)
    event=spawn('CompMusketeer')
    event.set_this_event_companion_front('CompMusketeer',true,nil)
    check('native companion recruitment remains compatible',event.actor.master.equal?($game_player) && event.follower[0]==1)
    $game_map.show_status_bars(event)
    check('RolePlay-S NPC status bar exists before saving',!$game_map.status_bars.empty?)
    $game_variables[995]=71014
    actor.stat[sk[:stage3_frames]]=314
    @class_saved=HeroClass.lona['initial'].dup
    scene.quickSave
    check('RolePlay-S quick save succeeds with an active status bar',File.file?(DataManager.userDataPath+'SavQuick.rvdata2'))
    check('save funnel clears transient status bars', $game_map.status_bars.empty?)
    $game_variables[995]=0
    @phase=:reload
    @ticks=0
    scene.quickLoad
  end

  def self.cold_boot
    check('cold process loads the combined native save',DataManager.load_custom_without_rescue('SavQuick')==true)
    $game_system.on_after_load
    SceneManager.goto(Scene_Map)
    if ['identity','identity_route'].include?(ModCompatProbe::CONFIG['phase'])
      first=$mod_manager.get_resource('RolePlayS','r1_PlainField4.rvdata2')
      second=$mod_manager.get_resource('RolePlayS','r4_RainFroest4.rvdata2')
      previous_map=$game_map.map_id_rec
      previous_ctx=LRD.ctx
      begin
        $game_map.instance_variable_set(:@map_id_rec,first)
        check('distinct registered map filenames are not the same current map',!LRD.current_map?({:map_id=>second}))
        LRD.ctx_set(previous_ctx.merge(:map_id=>first,:key=>'compat-other-map',:closed=>nil))
        check('registered map description keeps its own visit key',LRD.describe(second,false)['key']==LRD.key_for(second,nil,false))
      ensure
        $game_map.instance_variable_set(:@map_id_rec,previous_map)
        LRD.ctx_set(previous_ctx)
      end
      ModCompatProbe.finish if ModCompatProbe::CONFIG['phase']=='identity'
    end
    if ['classify','cold_maps'].include?(ModCompatProbe::CONFIG['phase'])
      [[1,'r1_PlainField4'],[4,'r4_RainFroest4'],[11,'r11_RoadPlain4']].each do |region,name|
        path=$mod_manager.get_resource('RolePlayS',name+'.rvdata2')
        raw=Note.get_data(load_data(path).note.to_s)
        check("registered map #{region} exposes its own region note",LRD.note_data(path)['region']==raw['region'] && raw['region'].to_i==region)
        check("registered map #{region} is classified as wild",LRD.class_for(path)==:wild)
      end
      ModCompatProbe.finish if ModCompatProbe::CONFIG['phase']=='classify'
    end
    @phase=:cold
    @ticks=0
  end

  def self.tick(scene)
    @ticks+=1
    raise "Native acceptance timed out #{@phase}" if @ticks>1500
    mode=FreeCombatPrototype::MapMode
    if @phase==:map && $game_map.map_id==@destination && !$game_player.transfer? && !@relocated
      point=nil
      (1...$game_map.height-1).each do |y|
        (1...$game_map.width-2).each do |x|
          if $game_map.passable?(x,y,6) && $game_map.passable?(x+1,y,4) &&
              $game_map.events.values.none? { |e| !e.deleted? && (e.x-x).abs<2 && (e.y-y).abs<2 }
            point=[x,y]; break
          end
        end
        break if point
      end
      raise 'No open native external-map fixture point' unless point
      mode.release
      $game_player.moveto(*point)
      $game_player.force_update=true
      mode.prepare
      @relocated=true
    end
    return unless mode.active? && !mode.session.suspended? && !$game_player.transfer?
    if @phase==:cold && ModCompatProbe::CONFIG['phase']=='identity_route'
      @return_map=$game_map.map_id
      @destination=$mod_manager.get_resource('RolePlayS','r1_PlainField4.rvdata2')
      $story_stats['ReRollHalfEvents']=1
      $game_player.reserve_transfer(@destination,1,1,2)
      @phase=:identity_first
      @ticks=0
      return
    end
    if @phase==:identity_first
      @first_visit=LRD.ctx
      @first_key=LRD.ctx[:key]
      check('first registered map has an active distinct visit',LRD.current_map? && [:wild,:lair].include?(LRD.ctx[:class]))
      @destination=$mod_manager.get_resource('RolePlayS','r4_RainFroest4.rvdata2')
      $story_stats['ReRollHalfEvents']=1
      $game_player.reserve_transfer(@destination,1,1,2)
      @phase=:identity_second
      @ticks=0
      return
    end
    if @phase==:identity_second
      check('second registered map opens its own visit',LRD.current_map? && LRD.ctx[:key]!=@first_key)
      check('old registered-map visit is no longer current',!LRD.current_map?(@first_visit))
      check('second registered map retains its region classification',LRD.note_data(@destination)['region'].to_i==4 && [:wild,:lair].include?(LRD.ctx[:class]))
      $story_stats['ReRollHalfEvents']=1
      $game_player.reserve_transfer(@return_map,73,57,8)
      @phase=:identity_back
      @ticks=0
      return
    end
    if @phase==:identity_back
      check('registered-map visit closes before the original town resumes',$game_map.map_id==@return_map && LRD.ctx[:key]!=@first_key && LRD.current_map?)
      ModCompatProbe.finish
      return
    end
    if @phase==:reload || @phase==:cold
      check('loaded story marker is preserved',$game_variables[995]==71014)
      check('loaded Temper data is preserved',$game_player.actor.stat[TemperTrine::STAT_KEYS[:stage3_frames]]==314)
      check('loaded RolePlay-S class data is valid',HeroClass.lona['initial'].is_a?(Array) && !HeroClass.lona['initial'].empty?)
      check('loaded Rest Journal describes the current map',LRD.ctx.is_a?(Hash) && !LRD.ctx[:key].nil?)
      check('loaded diagnostics and optimization hooks are healthy',FreeCombatDiagnostics.error.nil? && LonaPerformance.error.nil?)
      if @phase==:cold && ModCompatProbe::CONFIG['phase']!='cold_maps'
        ModCompatProbe.finish
        return
      end
      @return_map=$game_map.map_id
      id=$mod_manager.get_resource('RolePlayS','r1_PlainField4.rvdata2')
      check('RolePlay-S additional map resource is present',id.is_a?(String) && File.file?(id))
      $story_stats['ReRollHalfEvents']=1
      $game_player.reserve_transfer(id,1,1,2)
      @destination=id
      @phase=:map
      @ticks=0
      return
    end
    if @phase==:map
      check('continuous controller enters a RolePlay-S external map',$game_map.map_id==$data_mapinfos[@destination].id && mode.controls?($game_player))
      check('Rest Journal applies wild-map rules to the live additional map',[:wild,:lair].include?(LRD.ctx[:class]))
      check('external map builds reachable continuous geometry',mode.session.world.geometry.cells.size>1)
      @move_start=$game_player.real_x
      mode.session.combat.instance_variable_set(:@paused,false)
      ModCompatProbe.instance_variable_set(:@keys,[Input::SYM_KEYS[:RIGHT].first])
      @phase=:map_move
      @move_ticks=0
      return
    end
    if @phase==:map_move
      @move_ticks+=1
      return if @move_ticks<4
      check('external-map movement uses configured controls',$game_player.real_x>@move_start)
      ModCompatProbe.instance_variable_set(:@keys,[])
      $story_stats['ReRollHalfEvents']=1
      $game_player.reserve_transfer(@return_map,73,57,8)
      @phase=:back
      @ticks=0
      return
    end
    if @phase==:back
      check('external-map return rebuilds the controller',$game_map.map_id==@return_map && mode.controls?($game_player))
      check('Rest Journal closes and opens visits across external maps',LRD.ctx.is_a?(Hash) && !LRD.ctx[:key].nil?)
      ModCompatProbe.finish
    end
  end
end
