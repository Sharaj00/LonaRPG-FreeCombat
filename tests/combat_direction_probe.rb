# Run only in the private mod-compat-lab with its independently generated SavQuick.
module CombatDirectionProbe
  @lines = []
  def self.check(name, result)
    @lines << "#{result ? 'PASS' : 'FAIL'}: #{name}"
    File.open('combat-direction-verification.txt','w') { |file| file.puts(@lines) }
  end

  def self.boot
    raise 'Private save failed' unless DataManager.load_custom_without_rescue('SavQuick')
    $game_system.on_after_load
    SceneManager.goto(Scene_Map)
  end

  def self.run
    mode = FreeCombatPrototype::MapMode
    return unless mode.active? && !mode.session.suspended?
    return if @done
    @done = true
    session, player = mode.session, $game_player
    bridge, body = session.combat.effects, session.world.player
    ids = $game_map.events.keys
    $game_map.summon_event('CompMusketeer',player.x+3,player.y)
    target = $game_map.events[($game_map.events.keys-ids).first]
    raise 'Missing native target' unless target && target.actor
    session.combat.npcs.refresh
    token = session.combat.npcs.body(target)
    raise 'Target not controlled' unless token
    %w[WoodenClubNormal ShortSwordNormal WoodenSpearNormal].each do |name|
      sensor = $data_arpgskills[name].hit_detection
      [[0,1],[1,0],[0,-1],[-1,0],[Math.sqrt(0.5),Math.sqrt(0.5)]].each do |fx,fy|
        body.facing_x,body.facing_y=fx,fy
        token.x,token.y=body.x-fx*22,body.y-fy*22
        check(name+' rejects close rear '+[fx,fy].inspect,sensor.mine_number(player,target,false).nil?)
        token.x,token.y=body.x+fx*22,body.y+fy*22
        check(name+' retains close front '+[fx,fy].inspect,!!sensor.mine_number(player,target,false))
      end
    end
    body.facing_x,body.facing_y=0,1
    token.x,token.y=body.x,body.y-32
    check('circular attack retains rear zone',!!Sensors::SpinAttack.mine_number(player,target,false))
    check('explicit backward attack retains rear zone',!!Sensors::BackAttack.mine_number(player,target,false))
    # Exercise the production projectile initializer for player and NPC owners,
    # both inherited aim and a native targeted projectile. No fake damage is used.
    event_class=Struct.new(:id,:actor,:direction,:real_x,:real_y)
    event_class.class_eval do
      def set_direction(value); self.direction=value; end
    end
    actor_class=Struct.new(:target,:move_speed)
    [player,target].each_with_index do |owner,index|
      [[1,2],[2,1],[-1,2],[-2,1],[-1,-2],[-2,-1],[1,-2],[2,-1],[1,1]].each do |dx,dy|
        length=Math.sqrt(dx*dx+dy*dy)
        source_body=index==0 ? body : token
        source_body.facing_x,source_body.facing_y=dx/length,dy/length
        [false,true].each do |targeted|
          actor=actor_class.new(targeted ? Struct::FakeTarget.new(10+dx,10+dy) : nil,4)
          event=event_class.new(900001,actor,2,10,10)
          event.instance_variable_set(:@fcp_facing,[dx/length,dy/length])
          event.instance_variable_set(:@fcp_direction,2)
          bridge.start_projectile(event,{:user=>owner})
          shot=bridge.instance_variable_get(:@projectiles).delete(event.id)
          bridge.instance_variable_get(:@miles).delete(event.id)
          check(['cardinal projectile',index,dx,dy,targeted].inspect,
            (shot.dx==0) != (shot.dy==0))
          expected={2=>[0,2],4=>[-2,0],6=>[2,0],8=>[0,-2]}[event.direction]
          check('projectile velocity agrees with visible direction',expected==[shot.dx,shot.dy])
        end
      end
    end
    target.delete
    session.combat.npcs.refresh
    File.open('combat-direction-complete.txt','w') { |f| f.puts("#{@lines.count { |s| s.start_with?('PASS:') }} passed, #{@lines.count { |s| s.start_with?('FAIL:') }} failed") }
    exit
  rescue StandardError, ScriptError => error
    File.open('combat-direction-failure.txt','w') { |f| f.puts(error.class,error.message,error.backtrace) }
    exit
  end
end
class Scene_CombatDirectionBoot < Scene_Base
  def update; CombatDirectionProbe.boot; end
end
def SceneManager.first_scene_class; Scene_CombatDirectionBoot; end
class Scene_FreeCombatMap
  alias_method :direction_probe_update,:update
  def update
    direction_probe_update
    CombatDirectionProbe.run
  end
end
