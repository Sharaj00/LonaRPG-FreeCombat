# Native curved-event constructor coverage; no AI battle or user saves.
module CurvedArrowExtendedProbe
  @lines=[]
  def self.check(name,value)
    @lines << "#{value ? 'PASS' : 'FAIL'}: #{name}"
    File.open('curved-arrow-extended-verification.txt','w') { |file| file.puts(@lines) }
  end
  def self.boot
    raise 'Private save failed' unless DataManager.load_custom_without_rescue('SavQuick')
    $game_system.on_after_load
    SceneManager.goto(Scene_Map)
  end
  def self.tick
    mode=FreeCombatPrototype::MapMode
    return unless mode.active? && !mode.session.suspended?
    return if @done
    @done=true
    session=mode.session
    ids=$game_map.events.keys
    $game_map.summon_event('UndeadEliteBow',$game_player.x-4,$game_player.y-3)
    archer=$game_map.events[($game_map.events.keys-ids).first]
    raise 'Elite skeleton fixture failed' unless archer && archer.actor
    session.combat.npcs.refresh
    skill=$data_arpgskills['NpcCurvedArrow']
    [archer,$game_player].each do |owner|
      [[4,3],[3,4],[-4,3],[-3,4],[-4,-3],[-3,-4],[4,-3],[3,-4],[3,3],[0,0]].each do |dx,dy|
        target=Struct::FakeTarget.new(owner.x+dx,owner.y+dy)
        event=FreeCombatPrototype::NativeEffects.with_source(owner) do
          $game_map.ask_summon_event('ProjectileNpcCurvedArrow',nil,nil,-1,{:user=>owner,:target=>target,:skill=>skill})
        end
        delta=[event.x-owner.x,event.y-owner.y]
        label=(owner.equal?($game_player) ? 'player' : 'elite skeleton')+' '+[dx,dy].inspect
        check(label+' lands on one axis',delta[0]==0 || delta[1]==0)
        check(label+' preserves rounded distance',Math.sqrt(delta[0]**2+delta[1]**2).round==Math.sqrt(dx**2+dy**2).round)
        check(label+' keeps integer grid keys',event.x.is_a?(Integer) && event.y.is_a?(Integer))
        check(label+' preserves native arc',event.jumping? || dx==0 && dy==0)
        bridge=session.combat.effects
        previous=event.summon_data[:skill]
        event.summon_data[:skill]=$data_arpgskills['LongBowNormal']
        check(label+' does not remap non-curved effects',bridge.curved_displacement(event,dx,dy).nil?)
        event.summon_data[:skill]=previous
        event.delete
      end
    end
    archer.delete
    session.combat.npcs.refresh
    File.open('curved-arrow-extended-complete.txt','w') { |file| file.puts("#{@lines.count { |line| line.start_with?('PASS:') }} passed, #{@lines.count { |line| line.start_with?('FAIL:') }} failed") }
    exit
  rescue StandardError, ScriptError => error
    File.open('curved-arrow-extended-failure.txt','w') { |file| file.puts(error.class,error.message,error.backtrace) }
    exit
  end
end
class Scene_CurvedArrowExtendedBoot < Scene_Base
  def update; CurvedArrowExtendedProbe.boot; end
end
def SceneManager.first_scene_class; Scene_CurvedArrowExtendedBoot; end
class Scene_FreeCombatMap
  alias_method :curved_arrow_extended_update,:update
  def update
    curved_arrow_extended_update
    CurvedArrowExtendedProbe.tick
  end
end
