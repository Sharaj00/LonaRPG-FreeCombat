module CompanionPassageChecks
  def self.check(name,result)
    @lines << "#{result ? 'PASS' : 'FAIL'}: #{name}"
    File.open('companion-passage-verification.txt','w') { |file| file.puts(@lines) }
  end
  def self.collision(value)
    FreeCombatPrototype::Settings.send(:remove_const,:COMPANION_COLLISION)
    FreeCombatPrototype::Settings.const_set(:COMPANION_COLLISION,value)
  end
  def self.run(session)
    @lines=[]
    world,registry=session.world,session.combat.npcs
    lane=world.geometry.cells.find do |x,y|
      (0..3).all? { |i| !world.blocked?((x+i)*32+16,y*32+16,11) }
    end
    raise 'No companion test lane' unless lane
    ids=$game_map.events.keys
    $game_map.summon_event('CompMusketeer',lane[0]+1,lane[1])
    follower=$game_map.events[($game_map.events.keys-ids).first]
    raise 'No native follower' unless follower && follower.actor
    registry.refresh
    follower.set_this_event_companion_front('CompMusketeer',true,nil)
    token=registry.body(follower)
    raise 'Follower not controlled' unless token
    player=world.player
    player.x,player.y=lane[0]*32+16,lane[1]*32+16
    token.x,token.y=player.x+32,player.y
    session.sync_character($game_player,player)
    session.sync_character(follower,token)
    target=[token.x-19,token.y]
    collision(true)
    check('native recruit is recognized as player follower',follower.is_follower? && follower.actor.master.equal?($game_player))
    check('default companion blocks walking',world.occupied?(player,*target))
    check('default companion blocks through-route',!world.route_clear?(player,player.x+64,player.y))
    collision(false)
    check('option lets player enter companion space',!world.occupied?(player,*target))
    check('option lets companion enter player space',!world.occupied?(token,player.x+19,player.y))
    check('option removes companion as routing obstacle',world.route_clear?(player,player.x+64,player.y))
    before=player.x
    world.move(player,32,0)
    check('real player movement crosses the companion body',player.x>=before+31)
    player.x=before
    check('companion still exists as a combat target',session.combat.effects.characters.include?(follower))
    check('native event through flag is unchanged',!follower.through)
    old_master=follower.actor.master
    follower.actor.master=nil
    check('unowned NPC remains solid',world.occupied?(player,*target))
    follower.actor.master=old_master
    wall=[player.x+8,player.y-16,4,32]
    old_walls=world.walls
    world.instance_variable_set(:@walls,old_walls+[wall])
    check('walls still block player',world.occupied?(player,player.x+10,player.y))
    world.instance_variable_set(:@walls,old_walls)
    collision(true)
    check('collision can be restored',world.occupied?(player,*target))
    follower.delete
    registry.refresh
    check('deleted follower loses its body lookup',registry.character_for(token).nil?)
    File.open('companion-passage-complete.txt','w') { |file| file.puts("#{@lines.count { |line| line.start_with?('PASS:') }} passed, #{@lines.count { |line| line.start_with?('FAIL:') }} failed") }
  ensure
    collision(true)
  end
end
