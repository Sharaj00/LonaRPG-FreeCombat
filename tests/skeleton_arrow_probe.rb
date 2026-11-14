load_script 'companion-passage-checks.rb'
# Native skeleton bow regression, private runner and independent SavQuick only.
module SkeletonArrowProbe
  @phase, @ticks, @lines, @seen = :setup, 0, [], {}
  @checks=[]
  def self.observe_jump(event, before, after, requested)
    data=event.summon_data
    return unless data && data[:user].equal?(@archer) && data[:skill] && data[:skill].projectile_type==2
    delta=[after[0]-before[0],after[1]-before[1]]
    @checks << ['integer grid landing',after.all? { |value| value.is_a?(Integer) }]
    @checks << ['native jump distance retained',Math.sqrt(delta[0]**2+delta[1]**2).round==Math.sqrt(requested[0]**2+requested[1]**2).round]
    ok=delta[0]==0 || delta[1]==0
    @checks << [event.name,ok,delta]
    log([ok ? 'PASS' : 'FAIL','native curved landing is cardinal',event.name,delta].inspect)
  end
  CASES = %w[LongBowNormal NpcCurvedArrow]
  def self.log(value)
    @lines << value
    File.open('skeleton-arrow-trace.txt','w') { |file| file.puts(@lines) }
  end
  def self.boot
    File.open('skeleton-arrow-templates.txt','w') do |file|
      %w[ProjectileNpcCurvedArrow EffectArrow ArrowProjectile].each do |name|
        event=$data_EventLib[name]
        file.puts(name,event.inspect)
      end
    end
    raise 'Private fixture failed to load' unless DataManager.load_custom_without_rescue('SavQuick')
    $game_system.on_after_load
    SceneManager.goto(Scene_Map)
  end
  def self.tick
    mode=FreeCombatPrototype::MapMode
    return unless mode.active? && !mode.session.suspended?
    @ticks+=1
    session=mode.session
    if @phase==:setup
      @phase=:observe
      session.combat.instance_variable_set(:@paused,false)
      session.combat.npcs.events.values.dup.each { |event| event.delete }
      session.combat.npcs.refresh
      lane=session.world.geometry.cells.find do |x,y|
        [[x,y],[x+4,y+3]].all? do |px,py|
          !$game_map.events.values.any? { |event| !event.deleted? && (event.real_x-px).abs<2 && (event.real_y-py).abs<2 } &&
            !session.world.blocked?(px*32+16,py*32+16,11)
        end && session.world.clear_line?(x*32+16,y*32+16,(x+4)*32+16,(y+3)*32+16)
      end
      raise 'No diagonal native shooting lane' unless lane
      body=session.world.player
      body.x,body.y=(lane[0]+4)*32+16,(lane[1]+3)*32+16
      session.sync_character($game_player,body)
      ids=$game_map.events.keys
      $game_map.summon_event('UndeadBow',lane[0],lane[1])
      @archer=$game_map.events[($game_map.events.keys-ids).first]
      raise 'Skeleton did not spawn' unless @archer && @archer.actor
      session.combat.npcs.refresh
      raise 'Skeleton not continuously controlled' unless session.combat.npcs.registered?(@archer)
      @archer.actor.no_aggro=true
      @archer.move_type=0
      @archer.actor.instance_variable_set(:@target,$game_player)
      @case_index=0
      launch
    end
    session.combat.effects.events.values.each do |event|
      next if event.deleted?
      pos=[event.real_x,event.real_y]
      if !@seen.has_key?(event.object_id)
        @seen[event.object_id]=pos
        log(['SPAWN',CASES[@case_index],event.id,event.name,event.actor && event.actor.class,
          event.actor && event.actor.is_projectile,session.combat.effects.projectile?(event),pos,event.summon_data && event.summon_data.keys].inspect)
      elsif @seen[event.object_id]!=pos
        old=@seen[event.object_id]
        log(['MOVE',CASES[@case_index],event.id,event.name,pos[0]-old[0],pos[1]-old[1],pos].inspect)
        @seen[event.object_id]=pos
      end
    end
    if @ticks>=60
      session.combat.effects.events.values.dup.each { |event| event.delete unless event.deleted? }
      @archer.actor.reset_skill(true)
      @archer.actor.set_action_state(:none,true)
      @archer.animation=nil
      @case_index+=1
      if @case_index>=CASES.size
        CompanionPassageChecks.run(session)
        File.open('skeleton-arrow-complete.txt','w') { |f| f.puts("#{@checks.count { |row| row[1] }} passed, #{@checks.count { |row| !row[1] }} failed; checks=#{@checks.size}") }
        exit
      end
      launch
    end
  rescue StandardError, ScriptError => error
    File.open('skeleton-arrow-failure.txt','w') { |f| f.puts(error.class,error.message,error.backtrace) }
    exit
  end
  def self.launch
    @ticks=0
    @seen={}
    actor=@archer.actor
    actor.sta=actor.battle_stat.get_stat('sta',3)
    skill=$data_arpgskills[CASES[@case_index]]
    accepted=FreeCombatPrototype::NativeEffects.with_source(@archer) { actor.launch_skill(skill,true) }
    log(['LAUNCH',skill.name,accepted,actor.skill && actor.skill.name].inspect)
  end
end
class Scene_SkeletonArrowBoot < Scene_Base
  def update; SkeletonArrowProbe.boot; end
end
def SceneManager.first_scene_class; Scene_SkeletonArrowBoot; end
class Scene_FreeCombatMap
  alias_method :skeleton_arrow_original_update,:update
  def update
    skeleton_arrow_original_update
    SkeletonArrowProbe.tick
  end
end

class Game_Character
  alias_method :skeleton_probe_native_jump,:jump
  def jump(dx,dy,peak=10)
    before=[x,y]
    result=skeleton_probe_native_jump(dx,dy,peak)
    SkeletonArrowProbe.observe_jump(self,before,[x,y],[dx,dy]) if respond_to?(:summon_data)
    result
  end
end
