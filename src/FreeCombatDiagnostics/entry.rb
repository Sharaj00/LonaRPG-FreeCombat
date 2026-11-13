base = File.dirname(__FILE__)
['test_world.rb', 'arena.rb', 'test_modes.rb', 'overlay.rb'].each { |name| load_script "#{base}/#{name}" }

# RGSS301 / Ruby 1.9.2. Instrument only synchronous boundaries, never a yielding Fiber body.
module FreeCombatDiagnostics
  VERSION = '0.2.2'
  LIMIT = 4 * 1024 * 1024
  class << self
    attr_reader :error, :path
  end

  def self.clock
    @counter.call(@buffer)
    words = @buffer.unpack('L2')
    (words[0] + words[1] * 4294967296.0) / @frequency
  end

  def self.json(value)
    case value
    when Hash then '{' + value.map { |k,v| json(k.to_s) + ':' + json(v) }.join(',') + '}'
    when Array then '[' + value.map { |v| json(v) }.join(',') + ']'
    when String
      '"' + value.gsub(/["\\\x00-\x1f]/) { |c| c == '"' ? '\\"' : (c == '\\' ? '\\\\' : '\\u%04x' % c.ord) } + '"'
    when Numeric then value.to_s
    when TrueClass then 'true'
    when FalseClass then 'false'
    when NilClass then 'null'
    else json(value.to_s)
    end
  end

  def self.emit(kind, data = {})
    return if @error || !@path
    row = {'event'=>kind, 'time'=>Time.now.strftime('%Y-%m-%d %H:%M:%S'), 'frame'=>Graphics.frame_count, 'data'=>data}
    line = json(row) + "\n"
    if File.file?(@path) && File.size(@path) + line.bytesize > LIMIT
      File.delete(@path+'.2') if File.file?(@path+'.2')
      File.rename(@path+'.1',@path+'.2') if File.file?(@path+'.1')
      File.rename(@path,@path+'.1')
    end
    File.open(@path,'ab') { |f| f.write(line) }
  rescue StandardError => error
    @error = "#{error.class}: #{error.message}"
  end

  def self.context(nearby = false)
    map, player = $game_map, $game_player
    return {} unless map && player && player.actor
    mode = FreeCombatPrototype::MapMode
    session = mode.active? && mode.session
    events = map.events.values
    data = {'map_id'=>map.map_id, 'size'=>[map.width,map.height], 'events'=>events.size,
      'scene'=>SceneManager.scene.class.to_s, 'story'=>mode.story?, 'active'=>!!session,
      'player'=>[player.real_x,player.real_y,player.direction,player.actor.action_state.to_s],
      'interpreter'=>map.interpreter.running?, 'message'=>$game_message.busy?}
    if session
      combat, world = session.combat, session.world
      data.merge!('paused'=>combat.paused, 'npcs'=>combat.npcs.events.size, 'effects'=>combat.effects.events.size,
        'projectiles'=>combat.effects.instance_variable_get(:@projectiles).size,
        'routes'=>(world.instance_variable_get(:@route_jobs) || {}).size,
        'route_queue'=>(world.instance_variable_get(:@route_queue) || []).size)
    end
    if nearby
      close = events.select { |e| e.actor && !e.deleted? && (e.real_x-player.real_x).abs<=12 && (e.real_y-player.real_y).abs<=12 }
      data['nearby'] = close.sort_by { |e| (e.real_x-player.real_x)**2+(e.real_y-player.real_y)**2 }.first(24).map do |e|
        a=e.actor
        {'id'=>e.id,'npc'=>a.npc_name,'position'=>[e.real_x,e.real_y],'state'=>a.action_state.to_s,
         'object'=>a.is_object,'projectile'=>a.is_projectile,'controlled'=>!!(session && session.combat.npcs.registered?(e))}
      end
      data['equipment'] = player.actor.equips.compact.map { |i| i.item_name }
    end
    data
  rescue StandardError => error
    {'context_error'=>"#{error.class}: #{error.message}"}
  end

  def self.exception(error, origin)
    return if @last_exception.equal?(error)
    @last_exception = error
    emit('exception', {'origin'=>origin,'class'=>error.class.to_s,'message'=>error.message,
      'backtrace'=>error.backtrace,'context'=>context(true)})
    flush('exception')
  end

  def self.measure(label)
    return yield unless @in_frame && !@error
    started = clock
    begin
      yield
    ensure
      elapsed = (clock-started)*1000
      row = (@stages[label] ||= [0,0.0,0.0])
      row[0]+=1; row[1]+=elapsed; row[2]=elapsed if elapsed>row[2]
      @frame_stages[label] = (@frame_stages[label] || 0.0) + elapsed
    end
  end

  def self.hook(klass, name, label)
    original = klass.instance_method(name)
    klass.send(:define_method,name) do |*args,&block|
      FreeCombatDiagnostics.measure(label) { original.bind(self).call(*args,&block) }
    end
  end

  def self.stats(values)
    return nil if values.empty?
    sorted=values.sort
    {'count'=>sorted.size,'mean_ms'=>sorted.inject(0.0) { |s,v| s+v }/sorted.size,
     'p95_ms'=>sorted[(sorted.size*0.95).ceil-1], 'p99_ms'=>sorted[(sorted.size*0.99).ceil-1], 'max_ms'=>sorted.last}
  end

  def self.flush(reason)
    @previous=nil if reason=='scene_exit'
    return unless @frames && !@frames.empty?
    emit('performance', {'reason'=>reason,'context'=>context,'frame_wall'=>stats(@frames),
      'start_intervals'=>stats(@intervals),'graphics_wall'=>stats(@graphics),
      'gc_count_delta'=>GC.respond_to?(:count) ? GC.count-@gc_start : nil,
      'stages_inclusive_calls_total_max_ms'=>@stages,'slow_frames'=>@slow, 'slow_samples'=>@samples,
      'effect_events'=>@effect_count,'effect_samples'=>@effect_samples})
    @frames, @intervals, @graphics, @stages, @samples, @slow = [], [], [], {}, [], 0
    @effect_samples, @effect_count = [], 0
    @gc_start=GC.count if GC.respond_to?(:count)
    @flushed=clock
  end

  def self.frame
    return yield unless @installed && !@error && !@in_frame
    started=clock
    map_key=[$game_map.object_id,$game_map.map_id]
    if @map_key!=map_key
      flush('map_change')
      @previous=nil
      @map_key=map_key
      emit('map_enter',context(true))
    end
    @frame_stages={}
    @in_frame=true
    begin
      yield
    rescue StandardError, ScriptError => error
      exception(error,'scene_update')
      raise
    ensure
      @in_frame=false
      elapsed=(clock-started)*1000
      interval=@previous && (started-@previous)*1000
      @previous=started
      @frames << elapsed
      @intervals << interval if interval
      @graphics << (@frame_stages['graphics'] || 0.0)
      if elapsed>=50 || (interval && interval>=50)
        @slow+=1
        # Bound burst samples; totals still count every slow frame in the window.
        @samples << {'frame'=>Graphics.frame_count,'wall_ms'=>elapsed,'interval_ms'=>interval,'stages_ms'=>@frame_stages} if @samples.size<12
      end
      flush('periodic') if clock-@flushed>=5 || @frames.size>=600
    end
    if Input.trigger?(:F11)
      flush('user_marker')
      emit('user_marker',context(true))
    end
  end

  def self.install
    return if @installed || @error
    return unless defined?(FreeCombatPrototype::StorySaves)
    @buffer="\0"*8
    @counter=Win32API.new('kernel32','QueryPerformanceCounter','p','i')
    frequency=Win32API.new('kernel32','QueryPerformanceFrequency','p','i')
    raise 'Performance clock unavailable' if frequency.call(@buffer)==0
    words=@buffer.unpack('L2'); @frequency=words[0]+words[1]*4294967296.0
    dir=DataManager.userDataPath+'FreeCombatDiagnostics'
    Dir.mkdir(dir) unless File.directory?(dir)
    @path=dir+'/diagnostics.jsonl'
    @frames,@intervals,@graphics,@stages,@samples,@slow=[],[],[],{},[],0
    @effect_samples,@effect_count=[],0
    @gc_start=GC.count if GC.respond_to?(:count)
    @flushed=clock
    # First scene starts after LonaPerformance installs its guarded hooks.
    hook(FreeCombatPrototype::MapSession,:update_player,'player_controller')
    hook(class << FreeCombatPrototype::MapMode; self; end,:prepare,'map_prepare')
    hook(FreeCombatPrototype::MapNPCs,:refresh,'npc_registry')
    hook(FreeCombatPrototype::MapNPCs,:tick,'npc_steering')
    hook(FreeCombatPrototype::MapWorld,:route_between,'route_slices')
    hook(FreeCombatPrototype::MapWorld,:refresh_event_walls,'collision_index')
    hook(Game_Map,:update_events,'native_events')
    hook(Scene_FreeCombatMap,:draw_fcp_overlay,'combat_overlay')
    hook(Spriteset_Map,:update,'map_sprites')
    hook(FreeCombatPrototype::NativeEffects,:prune,'effect_update')
    hook(class << Graphics; self; end,:update,'graphics')
    @installed=true
    emit('session_start',{'version'=>VERSION,'ruby'=>RUBY_DESCRIPTION,
      'combat_version'=>$mod_manager['FreeCombatPrototype'].version,
      'performance'=>defined?(LonaPerformance) ? LonaPerformance.status : nil,
      'limits'=>{'window_seconds'=>5,'slow_threshold_ms'=>50,'slow_samples'=>12,'files'=>3,'file_bytes'=>LIMIT},
      'timings'=>'Inclusive wall time; graphics includes render/wait. Intervals include focus/OS pauses. No GC profiler or call tracing.'})
  rescue StandardError => error
    @error="#{error.class}: #{error.message}"
    prp "Free Combat Diagnostics disabled: #{@error}"
  end

  def self.effect(event)
    return unless @installed && !@error
    @effect_count+=1
    if @effect_samples.size<6
      @effect_samples << {'id'=>event.id,'name'=>event.name,'frame'=>Graphics.frame_count,'context'=>context(true)}
    end
  end
end

class Scene_Base
  alias_method :fcd_original_main,:main
  def main
    FreeCombatDiagnostics.install
    fcd_original_main
  rescue StandardError, ScriptError => error
    FreeCombatDiagnostics.exception(error,'scene_main')
    raise
  ensure
    FreeCombatDiagnostics.flush('scene_exit')
  end
end

class Scene_FreeCombatMap
  alias_method :fcd_original_update,:update
  def update
    FreeCombatDiagnostics.frame { fcd_original_update }
  end
end

class << FreeCombatPrototype::StorySaves
  alias_method :fcd_original_write,:write
  def write(paths,&block)
    result=fcd_original_write(paths,&block)
    FreeCombatDiagnostics.emit('save_result',{'files'=>paths.map { |p| File.basename(p) },'result'=>result})
    result
  rescue StandardError, ScriptError => error
    FreeCombatDiagnostics.exception(error,'save_write')
    raise
  end
end

class FreeCombatPrototype::NativeEffects
  alias_method :fcd_original_register,:register
  def register(event,data)
    result=fcd_original_register(event,data)
    if event && event.name.to_s =~ /Lantern|Fire|Trap/i
      FreeCombatDiagnostics.effect(event)
    end
    result
  end
end

load_script "#{base}/combat_journal.rb"
