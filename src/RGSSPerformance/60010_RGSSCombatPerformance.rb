# FreeCombatPrototype 0.7.1-0.7.2 only. No skipped AI/event updates or GC policy changes.
module RGSSCombatPerformance
  class << self
    attr_accessor :native_geometry, :dispatch_gates
    attr_reader :kernel
  end
  self.native_geometry = true
  self.dispatch_gates = true
  EMPTY = '' # Win32API rejects frozen pointer buffers, including empty ones.
  dll = const_defined?(:DLL_PATH) ? DLL_PATH : 'ModScripts/RGSSCombatPerformance/geometry-x86.dll'
  begin
    abi = Win32API.new(dll, 'lona_geometry_abi', '', 'i')
    raise 'Geometry DLL ABI mismatch' unless abi.call == 0x010101
    @kernel = Win32API.new(dll, 'lona_geometry', 'pplplpl', 'i')
  rescue StandardError, LoadError => error
    @kernel = nil
    prp "RGSSCombatPerformance: native geometry unavailable: #{error.message}"
  end

  def self.supported?(klass, method, suffix)
    location = klass.instance_method(method).source_location
    location && location[0].gsub('\\','/').end_with?(suffix)
  end

  def self.query(world, x1,y1,x2,y2,radius,point)
    return nil unless native_geometry && kernel
    values=[x1,y1,x2,y2,radius,point]
    return nil unless values.all? { |v| v.is_a?(Numeric) && v.to_f.finite? && v.abs < 10000000 }
    walls=world.walls
    unless world.instance_variable_get(:@perf_native_walls).equal?(walls)
      return nil unless walls.all? { |w| w.is_a?(Array) && w.size==4 && w.all? { |n| n.is_a?(Integer) && n.abs<10000000 } && w[2]>=0 && w[3]>=0 }
      world.instance_variable_set(:@perf_native_wall_bytes,walls.flatten.pack('d*'))
      world.instance_variable_set(:@perf_native_walls,walls)
    end
    bodies=world.instance_variable_get(:@routing_bodies)
    body_values=[]
    if bodies
      bodies.each { |b| body_values.push(b.x,b.y,b.radius) }
    end
    ignored=world.instance_variable_get(:@ignored_event_walls)
    if ignored
      return nil unless ignored.is_a?(Array) && ignored.all? { |w| w.is_a?(Array) && w.size==4 && w.all? { |n| n.is_a?(Integer) && n.abs<10000000 } }
    end
    ignore_bytes=ignored ? ignored.flatten.pack('d*') : EMPTY
    result=kernel.call(values.pack('d*'),world.instance_variable_get(:@perf_native_wall_bytes),walls.size,
      body_values.empty? ? EMPTY : body_values.pack('d*'),body_values.size/3,ignore_bytes,ignored ? ignored.size : 0)
    result<0 ? nil : result==1
  end
end

info_path='ModScripts/_Mods/FreeCombatPrototype/_ModInfo.json'
info=File.file?(info_path) ? JSON.decode(File.read(info_path)) : {}
if ['0.7.1','0.7.2','0.8.0','0.8.1','0.8.2','0.8.3','0.8.4','0.8.5','0.8.6','0.8.7','0.8.8','0.8.9','0.8.10','0.8.11'].include?(info['version']) && defined?(FreeCombatPrototype::MapWorld)
  world=FreeCombatPrototype::MapWorld
  if RGSSCombatPerformance.supported?(world,:blocked?,'/FreeCombatPrototype/map_world.rb') &&
      RGSSCombatPerformance.supported?(world,:clear_line?,'/FreeCombatPrototype/core.rb') &&
      RGSSCombatPerformance.supported?(world,:collision_walls,'/FreeCombatPrototype/map_world.rb')
    world.class_eval do
      alias_method :perf_combat_original_blocked?, :blocked?
      alias_method :perf_combat_original_clear_line?, :clear_line?
      def blocked?(x,y,radius)
        return perf_combat_original_blocked?(x,y,radius) unless @geometry
        left,top,right,bottom=navigation_bounds
        return true if x-radius<left || y-radius<top || x+radius>right || y+radius>bottom
        result=RGSSCombatPerformance.query(self,x,y,x,y,radius,1)
        result.nil? ? perf_combat_original_blocked?(x,y,radius) : result
      end
      def clear_line?(x1,y1,x2,y2,radius=0)
        result=RGSSCombatPerformance.query(self,x1,y1,x2,y2,radius,0)
        result.nil? ? perf_combat_original_clear_line?(x1,y1,x2,y2,radius) : !result
      end
    end
  end
  if defined?(Game_Event) && RGSSCombatPerformance.supported?(Game_Event,:fcp_npc_controller,'/FreeCombatPrototype/map_npcs.rb') &&
      RGSSCombatPerformance.supported?(Game_Event,:npc_original_update,'/FreeCombatPrototype/map_mode.rb')
    class Game_Event
      alias_method :perf_combat_original_controller, :fcp_npc_controller
      alias_method :perf_combat_original_native_update, :npc_original_update
      def fcp_npc_controller
        return perf_combat_original_controller unless RGSSCombatPerformance.dispatch_gates
        session=FreeCombatPrototype::MapMode.session
        controller=session && session.combat && session.combat.npcs
        return nil unless controller && controller.events[id].equal?(self)
        bridge=FreeCombatPrototype::NativeEffects.current
        controller if bridge && controller.registered?(self)
      end
      def npc_original_update
        return perf_combat_original_native_update unless RGSSCombatPerformance.dispatch_gates
        session=FreeCombatPrototype::MapMode.session
        return fcp_original_update unless session && equal?(session.opponent)
        perf_combat_original_native_update
      end
    end
  end
end
