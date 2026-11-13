module PrototypeChecks
  def self.check(name)
    raise "FAIL: #{name}" unless yield
    @results << "PASS: #{name}"
  end

  def self.save_bitmap(bitmap, path)
    width, height = bitmap.width, bitmap.height
    stride = (width * 3 + 3) & ~3
    pixels = ''
    (height - 1).downto(0) do |y|
      row = ''
      width.times do |x|
        color = bitmap.get_pixel(x, y)
        row << [color.blue.to_i, color.green.to_i, color.red.to_i].pack('C3')
      end
      pixels << row << "\x00" * (stride - width * 3)
      Graphics.update if y % 32 == 0
    end
    header = 'BM' + [54 + pixels.bytesize, 0, 54, 40, width, height].pack('V6') +
      [1, 24].pack('v2') + [0, pixels.bytesize, 0, 0, 0, 0].pack('V6')
    File.open(path, 'wb') { |file| file.write(header + pixels) }
  end

  def self.wait_for_enemy(world, frames = 650)
    frames.times do |frame|
      started = Time.now
      world.update(0, 0)
      elapsed = Time.now - started
      @navigation_cpu_time = (@navigation_cpu_time || 0) + elapsed
      @navigation_peak = [@navigation_peak || 0, elapsed].max
      @navigation_frames = (@navigation_frames || 0) + 1
      raise 'Enemy entered wall while navigating' if world.blocked?(world.enemy.x, world.enemy.y, world.enemy.radius)
      raise 'Non-finite navigation coordinate' unless world.enemy.x.to_f.finite? && world.enemy.y.to_f.finite?
      return true if world.player.hp < 100
      Graphics.update if frame % 60 == 0
    end
    false
  end

  def self.run
    @results = []
    File.delete("failure.txt") if File.exist?("failure.txt")
    File.delete("verification.txt") if File.exist?("verification.txt")
    world = FreeCombatPrototype::World.new
    world.update(1, 0)
    check('continuous sub-tile movement') { (world.player.x - 98.6).abs < 0.00001 }
    cardinal = world.player.x - 96
    world = FreeCombatPrototype::World.new
    world.update(1, 1)
    diagonal = Math.sqrt((world.player.x - 96) ** 2 + (world.player.y - 192) ** 2)
    check('diagonal speed is normalized') { (diagonal - cardinal).abs < 0.00001 }
    world.update(0, 0)
    x = world.player.x
    world.update(0, 0)
    check('stops between tiles') { world.player.x == x && x % 32 != 0 }
    world.move(world.player, 1000, 0)
    check('fast movement cannot tunnel through wall') { world.player.x <= 238 && !world.blocked?(world.player.x, world.player.y, 10) }
    world.player.x, world.player.y = 237, 180
    world.move(world.player, 15, 15)
    check('slides along walls') { world.player.x <= 238 && world.player.y > 180 }
    world.player.x, world.player.y = 300, 192
    world.enemy.x, world.enemy.y = 330, 192
    world.move(world.player, 30, 0)
    check('actor bodies cannot overlap') { world.enemy.x - world.player.x >= 21 }
    world.player.x, world.player.y = 300, 192
    world.player.facing_x = 1
    world.melee
    check('melee deals damage in facing direction') { world.enemy.hp == 75 }
    world.melee
    check('melee cooldown prevents repeated damage') { world.enemy.hp == 75 }
    world.player.cooldown = 0
    world.player.facing_x = -1
    world.melee
    check('melee does not hit behind player') { world.enemy.hp == 75 }
    world.player.x, world.enemy.x = 237, 291
    world.player.facing_x = 1
    world.player.cooldown = 0
    world.melee
    check('melee is blocked by walls') { world.enemy.hp == 75 }
    world.fire
    12.times { world.update_shots }
    check('projectile is blocked by walls') { world.enemy.hp == 75 && world.shots.empty? }
    world = FreeCombatPrototype::World.new
    world.player.x, world.enemy.x = 300, 370
    world.fire
    world.fire
    check('projectile cooldown') { world.shots.size == 1 }
    12.times { world.update_shots }
    check('projectile damages once and despawns') { world.enemy.hp == 80 && world.shots.empty? }
    world.shots << FreeCombatPrototype::Shot.new(300, 192, 160, 0, 10)
    world.update_shots
    check('fast projectile cannot tunnel through enemy') { world.enemy.hp == 60 && world.shots.empty? }
    world.shots << FreeCombatPrototype::Shot.new(300, 100, 0, 0, 1)
    world.update_shots
    check('projectile lifetime is bounded') { world.shots.empty? }
    world = FreeCombatPrototype::World.new
    world.enemy.x, world.enemy.y = 180, 100
    world.player.x, world.player.y = 96, 100
    before = world.enemy.x
    world.update(0, 0)
    check('enemy moves continuously toward player') { world.enemy.x < before && world.enemy.x > before - 2 }
    world.enemy.x = world.player.x + 28
    world.update(0, 0)
    hp = world.player.hp
    world.update(0, 0)
    check('enemy attack has damage and cooldown') { hp == 90 && world.player.hp == hp }
    world = FreeCombatPrototype::World.new
    1800.times do |frame|
      phase = (frame / 120) % 4
      dx, dy = [[1, 0], [0, 1], [-1, 0], [0, -1]][phase]
      world.update(dx, dy, frame % 24 == 0, frame % 20 == 0)
      [world.player, world.enemy].each do |body|
        raise 'Body entered wall during simulation' if world.blocked?(body.x, body.y, body.radius)
        raise 'Non-finite position' unless body.x.finite? && body.y.finite?
      end
    end
    check('1800-frame simulation preserves collision and finite coordinates') { true }
    world.enemy.hp = 0
    before = world.player.x
    world.update(1, 0, true, true)
    check('combat stops when encounter ends') { world.player.x == before }

    world = FreeCombatPrototype::World.new
    check('swept circle detects wall between clear endpoints') { !world.clear_line?(230, 142, 300, 142, 11) }
    check('tangent body can move away from wall') { world.clear_line?(291, 192, 304, 192, 11) }
    check('rounded body can leave a clear diagonal corner') { world.clear_line?(236, 140, 240, 144, 11) }
    navigation_started = Time.now
    world = FreeCombatPrototype::World.new
    check('enemy routes around central wall to stationary player') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.player.x, world.player.y = 160, 360
    world.enemy.x, world.enemy.y = 160, 280
    check('enemy routes around lower wall') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.player.x, world.player.y = 26, 90
    check('enemy reaches player touching room boundaries') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.player.x, world.player.y = 237, 192
    world.enemy.x, world.enemy.y = 291, 192
    check('enemy routes from wall edge without snapping into wall') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    100.times { world.update(0, 0) }
    world.player.x, world.player.y = 448, 360
    check('enemy replans after target changes sides') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.player.x, world.player.y = 224, 140
    world.enemy.x, world.enemy.y = 292, 284
    check('enemy safely rounds diagonal obstacle corners') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.enemy.x, world.enemy.y = 291.1, 192.3
    check('off-grid enemy near wall can join a route') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.walls[4] = [256, 144, 2, 144]
    world.player.x, world.player.y = 245, 192
    world.enemy.x, world.enemy.y = 269, 192
    check('enemy navigates even when close target is behind thin wall') { wait_for_enemy(world) }
    world = FreeCombatPrototype::World.new
    world.walls << [16, 224, 512, 16]
    world.player.x, world.player.y = 96, 300
    before = [world.enemy.x, world.enemy.y]
    class << world
      attr_reader :route_searches
      alias_method :original_find_enemy_path, :find_enemy_path
      def find_enemy_path
        @route_searches = (@route_searches || 0) + 1
        original_find_enemy_path
      end
    end
    reached = wait_for_enemy(world, 120)
    check('unreachable target does not cause wall crossing or false attacks') do
      !reached && [world.enemy.x, world.enemy.y] == before
    end
    check('stationary unreachable target is searched only once') { world.route_searches == 1 }
    File.open('navigation-timing.txt', 'w') { |f| f.puts("Navigation checks: #{Time.now - navigation_started} seconds including graphics yields", "Update sum: #{@navigation_cpu_time}; frames: #{@navigation_frames}; maximum update: #{@navigation_peak}") }

    fake_map_class = Class.new do
      attr_reader :width, :height
      attr_accessor :blocked_edge
      def initialize
        @width, @height = 10, 8
      end
      def valid?(x, y)
        x >= 0 && x < @width && y >= 0 && y < @height
      end
      def passable?(x, y, direction)
        valid?(x, y) && x.between?(1, 8) && y.between?(1, 6) &&
          (x != 4 || y == 3) && @blocked_edge != [x, y, direction]
      end
    end
    event_class = Struct.new(:x, :y, :through, :erased) do
      def deleted?; false; end
      def normal_priority?; true; end
    end
    map = fake_map_class.new
    map_world = FreeCombatPrototype::MapWorld.new(map, 80, 112, 208, 112)
    check('map geometry keeps open door passage passable') { map_world.clear_line?(80, 112, 208, 112, 11) }
    check('map geometry blocks solid map tiles') { map_world.blocked?(144, 80, 10) }
    check('connected floor is indexed independently of region IDs') { map_world.geometry.include?(6,3) && !map_world.geometry.include?(4,2) }
    separated = fake_map_class.new
    def separated.passable?(x,y,d); valid?(x,y) && [1,7].include?(x) && y==3; end
    left_room = FreeCombatPrototype::MapGeometry.new(separated,1,3)
    right_room = FreeCombatPrototype::MapGeometry.new(separated,7,3)
    check('disconnected room teleport selects a new component') { !left_room.include?(7,3) && right_room.include?(7,3) && !right_room.include?(1,3) }
    check('single-cell rooms do not require an opponent spawn') { left_room.cells.size==1 && right_room.cells.size==1 }
    door = event_class.new(4, 3, false, false)
    map_world.refresh_event_walls([door], nil)
    check('normal-priority event closes passage') { !map_world.clear_line?(80, 112, 208, 112, 11) }
    check('closed door prevents enemy reaching player') { !wait_for_enemy(map_world, 100) }
    door.through = true
    map_world.refresh_event_walls([door], nil)
    check('opening door invalidates route and permits pursuit') { wait_for_enemy(map_world, 300) }
    map = fake_map_class.new
    map.blocked_edge = [2, 3, 6]
    map_world = FreeCombatPrototype::MapWorld.new(map, 80, 112, 208, 112)
    check('directional tile restriction blocks its edge') { !map_world.clear_line?(80, 112, 112, 112, 10) }
    map_world = FreeCombatPrototype::MapWorld.new(fake_map_class.new, 80, 112, 208, 112)
    map_world.enemy.hp = 0
    map_world.update(1, 0)
    check('map player keeps moving after opponent defeat') { map_world.player.x > 80 }
    check('native map mode parses on Ruby 1.9') do
      RubyVM::InstructionSequence.compile(File.read('addon/map_mode.rb'))
      true
    end

    # Exercise the actual addon entry under a title stub, without Lona bootstrap.
    Object.const_set(:Scene_MapTitle, Class.new do
      attr_reader :original_calls
      def update
        @original_calls = (@original_calls || 0) + 1
      end
    end)
    def Object.load_script(path)
      eval(File.read(path), TOPLEVEL_BINDING, path)
    end
    # The game calls load_script as an inherited global method.
    Object.send(:define_method, :load_script) { |path| Object.load_script(path) }
    eval(File.read('addon/entry.rb'), TOPLEVEL_BINDING, 'addon/entry.rb')
    eval(File.read('diagnostics/test_world.rb'), TOPLEVEL_BINDING, 'diagnostics/test_world.rb')
    eval(File.read('diagnostics/arena.rb'), TOPLEVEL_BINDING, 'diagnostics/arena.rb')
    Input.update
    File.open('input-diagnostic.txt', 'w') do |f|
      f.puts("dir8=#{Input.dir8.inspect}")
      [:LEFT, :RIGHT, :UP, :DOWN].each { |key| f.puts("#{key}: #{Input.press?(key).inspect}") }
      [Input::LEFT, Input::RIGHT, Input::UP, Input::DOWN].each { |key| f.puts("#{key}: #{Input.press?(key).inspect}") }
    end
    title = Scene_MapTitle.new
    title.update
    check('entry preserves original title update without F6') { title.original_calls == 1 }

    # Verify F6 dispatch without opening an interactive loop in the check runner.
    input_class = class << Input; self; end
    input_class.send(:alias_method, :prototype_original_trigger, :trigger?)
    arena_class = FreeCombatPrototype::Arena
    arena_class.send(:alias_method, :prototype_original_run, :run)
    begin
      input_class.send(:define_method, :trigger?) { |key| key == :F6 }
      arena_class.send(:define_method, :run) { $prototype_arena_opened = true }
      $prototype_arena_opened = false
      title.update
      check('production F6 does not dispatch to arena') { !$prototype_arena_opened }
      check('production title keeps updating on F6') { title.original_calls == 2 }
    ensure
      input_class.send(:alias_method, :trigger?, :prototype_original_trigger)
      input_class.send(:remove_method, :prototype_original_trigger)
      arena_class.send(:alias_method, :run, :prototype_original_run)
      arena_class.send(:remove_method, :prototype_original_run)
      $prototype_arena_opened = nil
    end

    keyboard = FreeCombatPrototype::Keyboard.new
    keyboard.instance_variable_set(:@fake_keys, [])
    keyboard.instance_variable_set(:@fake_focus, true)
    def keyboard.held?(code); @fake_keys.include?(code); end
    def keyboard.focused?; @fake_focus; end
    keyboard.update
    check('arena ignores phantom RGSS directions') { !keyboard.down?(:up) && !keyboard.down?(:left) }
    keyboard.instance_variable_set(:@fake_keys, [0x27, 0x5A])
    keyboard.update
    check('keyboard direction and first attack press') { keyboard.down?(:right) && keyboard.trigger?(:melee) }
    keyboard.update
    check('holding attack does not create repeated presses') { keyboard.down?(:right) && !keyboard.trigger?(:melee) }
    keyboard.instance_variable_set(:@fake_focus, false)
    keyboard.update
    check('unfocused arena ignores keyboard') { !keyboard.down?(:right) && !keyboard.trigger?(:melee) }

    arena = FreeCombatPrototype::Arena.new
    arena.create_display
    arena.world.player.x, arena.world.player.y = 350, 220
    arena.world.enemy.x, arena.world.enemy.y = 390, 220
    arena.world.melee
    arena.world.fire
    arena.render
    Graphics.transition(0)
    3.times { Graphics.update }
    snapshot = Graphics.snap_to_bitmap
    check('renderer draws the arena in RGSS') { snapshot.get_pixel(20, 100).blue.to_i == 39 }
    save_bitmap(snapshot, 'arena.bmp')
    snapshot.dispose
    arena.dispose
    check('renderer disposes owned graphics') { arena.instance_variable_get(:@viewport).nil? && arena.instance_variable_get(:@sprite).disposed? }
    original_width, original_height = Graphics.width, Graphics.height
    small_arena = FreeCombatPrototype::Arena.new
    begin
      Graphics.resize_screen(640, 360)
      small_arena.create_display
      sprite = small_arena.instance_variable_get(:@sprite)
      check('arena fits 640x360 without clipping HUD or walls') do
        sprite.x >= 0 && sprite.y >= 0 &&
          sprite.x + sprite.bitmap.width * sprite.zoom_x <= Graphics.width + 0.5 &&
          sprite.y + sprite.bitmap.height * sprite.zoom_y <= Graphics.height + 0.5
      end
    ensure
      small_arena.dispose
      Graphics.resize_screen(original_width, original_height)
    end

    # Verify global adapters delegate outside the fresh test session without disk writes.
    Object.const_set(:Game_CharacterBase, Class.new { def moving?; :native_motion; end })
    Object.const_set(:Game_Actor, Class.new { def update_state_frames; :native_states; end })
    Object.const_set(:Game_Player, Class.new(Game_CharacterBase) do
      attr_accessor :x, :y, :real_x, :real_y, :direction
      def region_id; @test_region || 6; end
      def jumping?; false; end
      def cannot_control; false; end
      def update_animation; end
      def update_action_state; :native_action; end
      def update_normalmap; :native_normalmap; end
      def update; :native_player; end
      def moveto(x, y); [x, y]; end
    end)
    Object.const_set(:Game_Event, Class.new(Game_CharacterBase) { def update; :native_event; end })
    Object.const_set(:Scene_Map, Class.new { def terminate; end })
    Object.const_set(:DataManager, Module.new)
    class << DataManager
      def load_game(index); [:load, index]; end
      def save_game_without_rescue(index); [:manual, index]; end
      def save_doom_without_header; :doom; end
      def save_custom_without_header(name); [:custom, name]; end
      def make_save_screenshot(index); [:screenshot, index]; end
      def saveFileDeleteDoom; :delete; end
    end
    eval(File.read('addon/map_combat.rb'), TOPLEVEL_BINDING, 'addon/map_combat.rb')
    eval(File.read('addon/map_mode.rb'), TOPLEVEL_BINDING, 'addon/map_mode.rb')
    eval(File.read('diagnostics/test_modes.rb'), TOPLEVEL_BINDING, 'diagnostics/test_modes.rb')
    check('player adapter delegates outside map mode') { Game_Player.new.update == :native_player && Game_Player.new.moveto(2, 3) == [2, 3] }
    check('event and movement adapters delegate outside map mode') { Game_Event.new.update == :native_event && Game_Player.new.moving? == :native_motion }
    check('save adapters preserve original calls outside test session') do
      DataManager.save_game_without_rescue(7) == [:manual, 7] && DataManager.save_doom_without_header == :doom &&
        DataManager.save_custom_without_header('abc') == [:custom, 'abc'] &&
        DataManager.make_save_screenshot(8) == [:screenshot, 8] && DataManager.saveFileDeleteDoom == :delete
    end
    check('save loading delegates outside test mode') { DataManager.load_game(3) == [:load,3] }
    FreeCombatPrototype::MapMode.instance_variable_set(:@enabled, true)
    check('save loading is blocked inside test mode') { DataManager.load_game(3) == false }
    check('all save write and delete paths are blocked in test session') do
      [DataManager.save_game_without_rescue(7), DataManager.save_doom_without_header,
       DataManager.save_custom_without_header('abc'), DataManager.make_save_screenshot(8),
       DataManager.saveFileDeleteDoom].all? { |value| value == false }
    end
    saved_globals = [$game_player, $game_map, $game_message]
    begin
      $game_player = Game_Player.new
      $game_player.x, $game_player.y = 30, 20
      $game_player.real_x, $game_player.real_y, $game_player.direction = 30.2, 20.1, 8
      $game_message = Object.new
      def $game_message.busy?; false; end
      def $game_message.visible; false; end
      interpreter = Object.new
      def interpreter.running?; true; end
      $game_map = Struct.new(:map_id, :interpreter, :isOverMap).new(76, interpreter, false)
      map_data = Object.new
      $game_map.instance_variable_set(:@map, map_data)
      def $game_map.cam_target; 0; end
      def $game_map.tileset; @test_tileset ||= Object.new; end
      def $game_map.forced_block_dir; @test_blockers ||= []; end
      session = FreeCombatPrototype::MapSession.allocate
      world = FreeCombatPrototype::World.new
      world.player.x, world.player.y = (30.2 + 0.5) * 32, (20.1 + 0.5) * 32
      session.instance_variable_set(:@world, world)
      keyboard = Object.new
      def keyboard.update; end
      session.instance_variable_set(:@keyboard, keyboard)
      session.instance_variable_set(:@combat, Struct.new(:paused).new(false))
      $game_player.instance_variable_set(:@force_update, true)
      session.instance_variable_set(:@map_data, map_data)
      session.instance_variable_set(:@geometry_signature,session.geometry_signature)
      check('unchanged native passage data keeps existing geometry') { !session.geometry_changed? }
      $game_map.forced_block_dir << [2,3,4]
      check('in-place native directional blocker change invalidates geometry') { session.geometry_changed? }
      session.instance_variable_set(:@geometry_signature,session.geometry_signature)
      tile_event=Struct.new(:x,:y,:tile_id).new(1,2,300)
      $game_map.instance_variable_set(:@tile_events,[tile_event])
      check('native tile-event page change invalidates geometry') { session.geometry_changed? }
      session.instance_variable_set(:@last_direction, 2)
      def session.contains_player?; true; end
      FreeCombatPrototype::MapMode.instance_variable_set(:@session, session)
      FreeCombatPrototype::MapMode.instance_variable_set(:@target_map_id, 76)
      $game_player.instance_variable_set(:@test_region,4)
      check('tavern interior remains in free combat regardless of region') { FreeCombatPrototype::MapMode.active? }
      $game_map.map_id = 59
      check('old session cannot control a different map') { !FreeCombatPrototype::MapMode.active? }
      $game_map.map_id = 76
      $game_map.instance_variable_set(:@map, Object.new)
      check('reloaded map with the same ID cannot reuse a stale session') { !FreeCombatPrototype::MapMode.active? }
      $game_map.instance_variable_set(:@map, map_data)
      $game_player.instance_variable_set(:@test_region,6)
      before = [world.player.x, world.player.y]
      $game_player.update
      check('scripted turn updates attack direction without snapping position') do
        [world.player.x, world.player.y] == before && world.player.facing_x == 0 && world.player.facing_y == -1
      end
      released_actor=Object.new
      released_npc=Struct.new(:actor,:fcp_free_moving).new(released_actor,true)
      released_player=Struct.new(:actor,:fcp_free_moving).new(Object.new,true)
      release_effects=Struct.new(:events).new({})
      def release_effects.dispose(*args); end
      release_combat=Struct.new(:paused,:effects,:npcs).new(false,release_effects,Struct.new(:events).new({7=>released_npc}))
      release_combat.instance_variable_set(:@player, released_player.actor)
      release_effects.instance_variable_set(:@player, released_player)
      [released_actor,released_player.actor].each { |actor| actor.instance_variable_set(:@fcp_combat,release_combat) }
      $game_player=released_player
      FreeCombatPrototype::MapMode.instance_variable_set(:@session,Struct.new(:combat).new(release_combat))
      FreeCombatPrototype::MapMode.release
      check('map release detaches cached native actors from obsolete controllers') { [released_actor,released_player.actor].all? { |actor| actor.instance_variable_get(:@fcp_combat).nil? } }
      check('map release preserves running state and clears continuous movement flags') { FreeCombatPrototype::MapMode.session.nil? && FreeCombatPrototype::MapMode.instance_variable_get(:@paused)==false && !released_npc.fcp_free_moving && !released_player.fcp_free_moving }
    ensure
      $game_player, $game_map, $game_message = saved_globals
    end
    FreeCombatPrototype::MapMode.stop
    combat = FreeCombatPrototype::NativeCombat.allocate
    world = FreeCombatPrototype::World.new
    combat.instance_variable_set(:@world, world)
    skill = Struct.new(:range).new(1)
    world.player.x, world.player.y = 80, 80
    world.player.facing_x, world.player.facing_y = 1, 0
    world.enemy.x, world.enemy.y = 115, 80
    world.walls.clear
    check('native skill range uses continuous front-facing geometry') { combat.in_melee_range?(world.player, world.enemy, skill) }
    world.enemy.x = 150
    check('native melee misses outside equipped skill range') { !combat.in_melee_range?(world.player, world.enemy, skill) }
    world.enemy.x = 50
    check('native melee cannot hit behind the player') { !combat.in_melee_range?(world.player, world.enemy, skill) }
    world.enemy.x = 115
    world.walls << [96, 60, 4, 40]
    check('native melee cannot hit through a wall') { !combat.in_melee_range?(world.player, world.enemy, skill) }
    base = Class.new do
      def process_skill_result(skill); :native_result; end
      def summon_skill_user_efx(holding = false); :native_effect; end
    end
    actor = base.new
    actor.extend(FreeCombatPrototype::ContinuousSkills)
    check('combat adapter delegates when test session is disabled') { actor.process_skill_result(nil) == :native_result && actor.summon_skill_user_efx == :native_effect }
    actor = Struct.new(:health, :sta, :action_state).new(73, 41, :none)
    enemy = Struct.new(:health, :sta, :action_state).new(60, 300, :none)
    combat.instance_variable_set(:@player, actor)
    combat.instance_variable_set(:@enemy, enemy)
    combat.sync_health
    check('body HP mirrors native health instead of test defaults') { world.player.hp == 73 && world.enemy.hp == 60 }
    actor.sta = -100
    combat.sync_health
    check('native exhaustion stops free combat despite positive health') { world.player.hp == 0 && !combat.available?(actor) }
    actor.sta, actor.action_state = 40, :stun
    check('native stun blocks movement and attacks') { !combat.available?(actor) }

    indexed = FreeCombatPrototype::MapWorld.allocate
    budget_world = FreeCombatPrototype::MapWorld.allocate
    FreeCombatPrototype::World.instance_method(:initialize).bind(budget_world).call
    budget_world.instance_variable_set(:@geometry,Struct.new(:bounds).new([0,0,2240,2240]))
    budget_world.instance_variable_set(:@walls,[[1120,0,32,1800]])
    heap=[]
    [5,1,9,1,0,3].each { |value| budget_world.route_push(heap,[value,nil,nil]) }
    sorted_priorities=[]
    sorted_priorities << budget_world.route_pop(heap)[0] until heap.empty?
    check('route priority queue preserves ordering and duplicate priorities') { sorted_priorities==[0,1,1,3,5,9] }
    budget_world.player.x,budget_world.player.y=2080,2080
    chaser=FreeCombatPrototype::Body.new(80,80,11,100,1,0,0)
    started=Time.now
    pending_route=budget_world.route_between(chaser,2080,2080,budget_world.player)
    check('large-map path search yields instead of blocking the frame') { pending_route.nil? && Time.now-started<0.04 }
    check('yielded search restores live player and collision context') { budget_world.player.x==2080 && budget_world.player.y==2080 && budget_world.instance_variable_get(:@routing_bodies).nil? }
    path=nil
    4000.times do
      Graphics.update
      path=budget_world.route_between(chaser,2080,2080,budget_world.player)
      break unless path.nil?
    end
    check('budgeted path search eventually completes a long detour') { path && !path.empty? }
    abandoned=FreeCombatPrototype::Body.new(80,80,11,100,1,0,0)
    budget_world.route_between(abandoned,2080,2080,budget_world.player)
    budget_world.cancel_route(abandoned)
    neighbor=FreeCombatPrototype::Body.new(2040,2080,11,100,1,0,0)
    Graphics.update
    nearby_path=nil
    100.times do
      nearby_path=budget_world.route_between(neighbor,2080,2080,budget_world.player)
      break unless nearby_path.nil?
      Graphics.update
    end
    check('cancelled search does not block another NPC in the route queue') { nearby_path && !nearby_path.empty? && !budget_world.instance_variable_get(:@route_jobs).has_key?(abandoned.object_id) }
    FreeCombatPrototype::World.instance_method(:initialize).bind(indexed).call
    indexed.instance_variable_set(:@geometry, Struct.new(:bounds).new([0, 0, 1024, 640]))
    rectangles = (0...80).map { |i| [50 + (i % 10) * 96, 50 + (i / 10) * 64, 20 + (i % 3) * 20, 10 + (i % 5) * 5] }
    rectangles << [320, 0, 1, 400]
    indexed.instance_variable_set(:@walls, rectangles)
    reference = FreeCombatPrototype::World.new
    reference.instance_variable_set(:@walls, rectangles)
    random = Random.new(9017)
    parity = 300.times.all? do
      x1, x2 = random.rand(12..980), random.rand(12..980)
      y1, y2 = random.rand(12..600), random.rand(12..600)
      radius = random.rand(0..11)
      indexed.blocked?(x1, y1, radius) == reference.blocked?(x1, y1, radius) &&
        indexed.clear_line?(x1, y1, x2, y2, radius) == reference.clear_line?(x1, y1, x2, y2, radius)
    end
    check('spatial wall buckets preserve exact circle and swept collision') { parity }
    long_parity=[0,1,11,32,65].all? do |radius|
      [-60,-2,0,2,60].all? do |offset|
        indexed.clear_line?(-1000,-1000+offset,4000,4000+offset,radius)==reference.clear_line?(-1000,-1000+offset,4000,4000+offset,radius)
      end
    end
    check('thin-corridor wall lookup preserves long diagonal and wide-body collisions') { long_parity }
    buckets=indexed.instance_variable_get(:@wall_buckets).size
    indexed.collision_walls(-5000,-5000,5000,5000,11)
    check('empty-space collision queries do not grow the wall index') { indexed.instance_variable_get(:@wall_buckets).size==buckets }
    check('local collision ignores distant walls') { indexed.collision_walls(12, 12, 30, 12, 5).size < rectangles.size / 4 }
    indexed.instance_variable_set(:@walls, rectangles + [[20, 0, 2, 30]])
    check('changing event wall array rebuilds spatial collision buckets') { !indexed.clear_line?(12, 12, 30, 12) }

    dummy = Struct.new(:id, :x, :y).new(62, 2, 2)
    indexed.instance_variable_set(:@map, Struct.new(:events).new({62 => dummy}))
    indexed.instance_variable_set(:@walls, [[64,64,32,32], [110,64,2,32]])
    check('training target stays solid to player movement') { indexed.blocked?(80,80,10) }
    indexed.without_event_walls([dummy]) do
      check('training target does not occlude its own hit ray') { indexed.clear_line?(40,80,80,80) }
      check('training hit ray still respects unrelated walls') { !indexed.clear_line?(40,80,130,80) }
    end
    check('hit query restores training target collision') { indexed.blocked?(80,80,10) }

    moving = FreeCombatPrototype::Body.new(40.5,80.25,11,100,1,0,0)
    blocker = FreeCombatPrototype::Body.new(80.5,80.25,11,100,1,0,0)
    indexed.npc_bodies = {1=>moving,2=>blocker}
    indexed.instance_variable_set(:@walls,[])
    check('continuous NPC collision ignores its own body') { !indexed.occupied?(moving,40.5,80.25) }
    check('continuous NPC collision blocks other living actors') { indexed.occupied?(moving,69.5,80.25) }
    check('NPC navigation respects intervening NPC bodies') { !indexed.route_clear?(moving,120,80.25) }
    check('NPC navigation may approach its actual target') { indexed.route_clear?(moving,80.5,80.25,blocker) }
    check('NPC navigation filter does not affect later hit rays') { indexed.clear_line?(40.5,80.25,120,80.25) }
    original_player,original_enemy=indexed.player,indexed.enemy
    indexed.route_between(moving,120,80.25,blocker)
    check('NPC route search restores the real player and enemy') { indexed.player.equal?(original_player) && indexed.enemy.equal?(original_enemy) }
    blocker.hp=0
    check('dead NPC bodies do not block free movement') { !indexed.occupied?(moving,69.5,80.25) }
    moving.x,moving.y=40.5,indexed.player.y
    check('companion navigation routes around the player for a front position') { !indexed.route_clear?(moving,140,indexed.player.y) }
    check('companion may approach its actual player target') { indexed.route_clear?(moving,indexed.player.x,indexed.player.y,indexed.player) }

    projectile_world = FreeCombatPrototype::World.new
    projectile_world.walls.clear
    source, payload, target = Object.new, Object.new, Object.new
    shot = FreeCombatPrototype::NativeShot.new(80.0, 80.0, 8.0, 0.0, 90, source, payload)
    results = []
    3.times { results << FreeCombatPrototype::SkillGeometry.advance(shot, projectile_world, [[target, 100, 80, 11]]) }
    check('moving projectile retains native payload at swept impact') { results.include?(target) && shot.source.equal?(source) && shot.skill.equal?(payload) }
    projectile_world.walls << [90, 60, 4, 40]
    shot.x, shot.y = 80, 80
    check('native projectile stops at a wall before its victim') { FreeCombatPrototype::SkillGeometry.advance(shot, projectile_world, [[target, 120, 80, 11]]) == :wall }

    npc_controller = FreeCombatPrototype::MapNPCs.allocate
    npc_actor = Struct.new(:is_object,:is_projectile).new(false,false)
    npc_event = Struct.new(:id,:actor,:erased,:gone,:x,:y).new(13,npc_actor,false,false,0,0)
    def npc_event.deleted?; gone; end
    npc_controller.instance_variable_set(:@events,{13=>npc_event})
    npc_controller.instance_variable_set(:@cells,{[0,0]=>true})
    check('NPC registry recognizes the actual live event identity') { npc_controller.registered?(npc_event) }
    npc_event.x=3
    check('NPC teleported outside the courtyard delegates to native movement') { !npc_controller.registered?(npc_event) }
    npc_event.x=0
    npc_event.erased=true
    check('erased NPC immediately leaves continuous control') { !npc_controller.registered?(npc_event) }
    npc_event.erased=false
    npc_event.actor=nil
    check('NPC page without an actor delegates to native events') { !npc_controller.registered?(npc_event) }
    npc_event.actor=npc_actor
    npc_actor.is_object=true
    check('NPC page converted to an object leaves character movement') { !npc_controller.registered?(npc_event) }

    npc_actor.is_object=false
    npc_event.define_singleton_method(:real_x) { self.x }
    npc_event.define_singleton_method(:real_y) { self.y }
    token=FreeCombatPrototype::Body.new(16,16,11,100,0,1,0)
    npc_controller.instance_variable_set(:@bodies,{13=>token})
    npc_controller.instance_variable_set(:@orders,{13=>[16,48,nil,0]})
    npc_event.x=3
    npc_controller.sync_from(npc_event,token)
    check('teleport outside courtyard resynchronizes the retained body before unregistering') { token.x==112 && token.y==16 && npc_controller.instance_variable_get(:@orders).empty? }

    npc_event.x=0
    [[:gone,true],[:erased,true],[:x,3],[:actor,nil]].each do |attribute,value|
      previous=npc_event.send(attribute)
      npc_event.send((attribute.to_s+'=').to_sym,value)
      check('NPC tick skips native update invalidation: '+attribute.to_s) { npc_controller.tick(npc_event).nil? && token.x==112 && token.y==16 }
      npc_event.send((attribute.to_s+'=').to_sym,previous)
    end
    [:is_object,:is_projectile].each do |attribute|
      npc_actor.send((attribute.to_s+'=').to_sym,true)
      check('NPC tick skips native page conversion: '+attribute.to_s) { npc_controller.tick(npc_event).nil? && token.x==112 && token.y==16 }
      npc_actor.send((attribute.to_s+'=').to_sym,false)
    end
    def npc_event.is_follower?; false; end
    def npc_event.move_type; 0; end
    def npc_event.fcp_free_moving=(value); @moving=value; end
    FreeCombatPrototype::NativeEffects.with_source(npc_event,false) { npc_controller.request(npc_event,16,48) }
    check('ordinary NPC motion retains the skill/recovery gate') { npc_controller.instance_variable_get(:@orders)[13][6] == false }
    FreeCombatPrototype::NativeEffects.with_source(npc_event) { npc_controller.request(npc_event,16,48) }
    check('owned native effect motion may continue its active skill') { npc_controller.instance_variable_get(:@orders)[13][6] == true }
    npc_controller.request(npc_event,16,48)
    check('scripted NPC motion does not leak into later AI orders') { npc_controller.instance_variable_get(:@orders)[13][6] == false }
    pending_world=Object.new
    def pending_world.walls; @walls ||= []; end
    def pending_world.route_clear?(*args); false; end
    def pending_world.route_between(*args); nil; end
    def pending_world.cancel_route(*args); raise 'Pending route was cancelled'; end
    pending_recovery=Object.new
    def pending_recovery.busy?(actor); false; end
    pending_combat=Struct.new(:recovery).new(pending_recovery)
    def pending_combat.available?(actor); true; end
    def npc_actor.action_state; :none; end
    def npc_event.distance_per_frame; 0.0625; end
    npc_controller.instance_variable_set(:@world,pending_world)
    npc_controller.instance_variable_set(:@combat,pending_combat)
    npc_controller.instance_variable_set(:@routes,{})
    saved_session=FreeCombatPrototype::MapMode.session
    pending_session=Object.new
    def pending_session.sync_character(*args); end
    FreeCombatPrototype::MapMode.instance_variable_set(:@session,pending_session)
    begin
      before=[token.x,token.y]
      npc_controller.tick(npc_event)
      check('NPC retains its movement order while a route is pending') { npc_controller.instance_variable_get(:@orders).has_key?(13) && [token.x,token.y]==before }
    ensure
      FreeCombatPrototype::MapMode.instance_variable_set(:@session,saved_session)
    end

    landing_combat=Object.new
    def landing_combat.log(message); end
    landing_controller=FreeCombatPrototype::MapNPCs.allocate
    landing_controller.instance_variable_set(:@combat,landing_combat)
    landing_controller.instance_variable_set(:@events,{})
    landing_controller.instance_variable_set(:@bodies,{})
    landing_controller.instance_variable_set(:@cells,{[0,0]=>true})
    landing_actor=Struct.new(:health,:npc_name,:is_object,:is_projectile).new(100,'returning',false,false)
    landing_actor.instance_variable_set(:@fcp_combat,landing_combat)
    landing_event=Object.new
    class << landing_event
      attr_accessor :id,:actor,:x,:y,:real_x,:real_y,:erased
    end
    landing_event.id,landing_event.actor=19,landing_actor
    landing_event.x,landing_event.y,landing_event.real_x,landing_event.real_y=0,0,0,-12
    def landing_event.deleted?; false; end
    def landing_event.jumping?; @jump_count.to_i>0; end
    landing_event.instance_variable_set(:@jump_count,20)
    landing_controller.register(landing_event)
    check('returning native jump attaches at its courtyard landing instead of airborne origin') { landing_controller.body(landing_event).y==16 && landing_event.instance_variable_get(:@real_y)==0 }
    check('returning native jump completes before continuous interpolation takes over') { landing_event.instance_variable_get(:@jump_count)==0 }
    landing_event.id=20
    landing_event.real_x=0.2
    landing_event.real_y=0.3
    landing_controller.register(landing_event)
    check('ordinary NPC reattachment preserves fractional coordinates') { (landing_controller.body(landing_event).y-25.6).abs<0.001 }

    player_actor=Struct.new(:is_projectile,:immune_damage,:action_state).new(false,false,:none)
    check('NPC projectile accepts native player without NPC-only ignore flag') { !FreeCombatPrototype::NativeEffects.projectile_ignored?(player_actor) }
    player_actor.immune_damage=true
    check('NPC projectile still respects native player immunity') { FreeCombatPrototype::NativeEffects.projectile_ignored?(player_actor) }
    npc_projectile_target=Struct.new(:is_projectile,:immune_damage,:action_state,:ignore_projectile).new(false,false,:none,true)
    check('NPC projectile still honors NPC ignore-projectile flag') { FreeCombatPrototype::NativeEffects.projectile_ignored?(npc_projectile_target) }

    bridge = FreeCombatPrototype::NativeEffects.allocate
    bridge.instance_variable_set(:@combat,Object.new)
    check('native investigation coordinates work without a character actor') { bridge.position(Struct.new(:x,:y).new(3,4)) == [112,144] }

    selector_world=FreeCombatPrototype::World.new
    selector_world.player.x,selector_world.player.y=80,80
    selector_player=Object.new
    class << selector_player
      attr_accessor :crosshair,:bridge,:mouse_calls
      def move_crosshair_by_input
        self.mouse_calls=mouse_calls.to_i+1
        bridge.move_selector(crosshair,1,0)
      end
    end
    selector=Struct.new(:id,:x,:y,:real_x,:real_y).new(27,2,2,2,2)
    selector_player.crosshair,selector_player.bridge=selector,bridge
    selector.instance_variable_set(:@fcp_effects,bridge)
    bridge.instance_variable_set(:@world,selector_world)
    bridge.instance_variable_set(:@player,selector_player)
    bridge.instance_variable_set(:@selectors,{})
    selector_session=Object.new
    def selector_session.sync_character(event,body)
      event.x,event.y=(body.x/32).floor,(body.y/32).floor
      event.real_x,event.real_y=body.x/32.0-0.5,body.y/32.0-0.5
    end
    def selector_session.face(character,dx,dy); end
    previous_session=FreeCombatPrototype::MapMode.session
    added_mouse=!Object.const_defined?(:Mouse)
    Object.const_set(:Mouse,Module.new) if added_mouse
    class << Mouse
      attr_accessor :selector_test_enabled
      def enable?; @selector_test_enabled; end
    end
    begin
      FreeCombatPrototype::MapMode.instance_variable_set(:@session,selector_session)
      Mouse.selector_test_enabled=false
      bridge.move_selector(selector,1,0)
      moved=bridge.position(selector)[0]
      check('native selector direction uses continuous pixel speed') { (moved-82.6).abs<0.001 }
      check('selector motion consumes keyboard input without moving the player') { bridge.update_selector(0,0)==[0,0] && selector_world.player.x==80 }
      check('next selector update preserves native command progress') { (bridge.position(selector)[0]-moved).abs<0.001 }
      Mouse.selector_test_enabled=true
      bridge.update_selector(1,0)
      check('mouse selector uses the native command handler once instead of duplicating keyboard movement') { selector_player.mouse_calls==1 && (bridge.position(selector)[0]-moved-2.6).abs<0.001 }
    ensure
      FreeCombatPrototype::MapMode.instance_variable_set(:@session,previous_session)
      Object.send(:remove_const,:Mouse) if added_mouse
    end

    context = FreeCombatPrototype::NativeEffects
    source = Object.new
    context.with_source(source) do
      check('native effect context permits scripted continuation') { context.source.equal?(source) && context.scripted }
      context.with_source(source, false) { check('player launch context keeps recovery gate active') { !context.scripted } }
      check('nested skill context restores native continuation') { context.scripted }
    end
    check('native effect context does not leak into later input') { context.source.nil? && !context.scripted }

    token = Struct.new(:animation).new(Struct.new(:frames).new([[0,0,4],[1,0,2]]))
    actor = Struct.new(:map_token, :action_state, :health, :sta).new(token, :none, 200, 100)
    skill = Struct.new(:hit_frame).new(2)
    recovery = FreeCombatPrototype::ActionRecovery.new
    check('player recovery derives from complete native animation') { recovery.begin_action(actor, skill) == 7 }
    10.times { recovery.update }
    check('player cannot reset recovery while attack animation runs') { recovery.busy?(actor) }
    token.animation = nil
    6.times { recovery.update }
    check('player still waits during post-animation recovery') { recovery.busy?(actor) }
    recovery.update
    check('player can attack when recovery completes') { !recovery.busy?(actor) }
    recovery.begin_action(actor, skill)
    token.animation = Struct.new(:frames).new([[0,0,8],[1,0,3]])
    recovery.update
    token.animation = nil
    11.times { recovery.update }
    check('late native NPC animation extends attack recovery') { recovery.busy?(actor) }
    recovery.update
    check('late native animation recovery eventually completes') { !recovery.busy?(actor) }
    combat.instance_variable_set(:@recovery, recovery)
    check('common launch gate admits a recovered actor') { combat.can_launch?(actor) }
    recovery.begin_action(actor, skill)
    check('common launch gate rejects attacks after native actor state clears') { !combat.can_launch?(actor) }

    sensor = Object.new
    def sensor.center; [1,1]; end
    def sensor.detection_array; [[0,0,0],[0,['u',1],0],[0,0.5,0]]; end
    geo = FreeCombatPrototype::SkillGeometry
    check('native mask follows fractional source coordinates') { geo.weight(sensor, 93.5, 80.25, 0, 1, 93.5, 112.25, 0) == 0.5 }
    check('native mask turns continuously with diagonal aim') do
      v = Math.sqrt(0.5)
      geo.weight(sensor, 80, 80, v, v, 80+32*v, 80+32*v, 0) == 0.5
    end
    check('native mask keeps side gaps instead of a generic cone') { geo.weight(sensor, 80, 80, 0, 1, 112, 112, 0) == 0 }
    check('native mask intersects victim collision radius') { geo.weight(sensor, 80, 80, 0, 1, 103, 112, 8) == 0.5 }

    saved_globals = [$game_map, $game_message, $game_player]
    eval(File.read('diagnostics/overlay.rb'), TOPLEVEL_BINDING, 'diagnostics/overlay.rb')
    FreeCombatDiagnostics.toggle_overlay
    overlay = Sprite.new
    effects = Sprite.new
    begin
      $game_map = Struct.new(:map_id, :isOverMap).new(76, false)
      $game_player = Game_Player.new
      $game_message = Object.new
      def $game_message.busy?; false; end
      def $game_message.visible; false; end
      overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      effects.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      bitmap = overlay.bitmap
      def bitmap.draw_text(*args); @draw_calls = (@draw_calls || 0) + 1; end
      scene = Scene_FreeCombatMap.allocate
      scene.instance_variable_set(:@fcp_overlay, overlay)
      scene.instance_variable_set(:@fcp_effects, effects)
      scene.draw_fcp_overlay
      first = bitmap.instance_variable_get(:@draw_calls)
      scene.draw_fcp_overlay
      check('unchanged map HUD is not repainted every frame') { first > 0 && bitmap.instance_variable_get(:@draw_calls) == first }
      $game_map.map_id = 59
      scene.draw_fcp_overlay
      check('map HUD repaints when status changes') { bitmap.instance_variable_get(:@draw_calls) > first }
      $game_map.map_id = 76
      $game_player.instance_variable_set(:@test_region,4)
      scene.draw_fcp_overlay
      check('all-map HUD reports pending native events without a courtyard exclusion') { scene.instance_variable_get(:@fcp_hud_lines).any? { |line| line.include?('waiting for native map events') } }
      $game_map.isOverMap = true
      scene.draw_fcp_overlay
      check('overworld HUD describes native tile travel') { scene.instance_variable_get(:@fcp_hud_lines).any? { |line| line.include?('native tile movement') } }
    ensure
      overlay.bitmap.dispose if overlay.bitmap
      effects.bitmap.dispose if effects.bitmap
      overlay.dispose
      effects.dispose
      $game_map, $game_message, $game_player = saved_globals
    end

    File.open('verification.txt' , 'w') { |file| file.puts(@results); file.puts("TOTAL: #{@results.size} passed") }
  end
end
eval(File.read('movement_binding_checks.rb'), TOPLEVEL_BINDING, 'movement_binding_checks.rb')
rgss_main { MovementBindingChecks.run; PrototypeChecks.run }
