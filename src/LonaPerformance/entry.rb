# RGSS3 / Ruby 1.9.2. Install once, after the game's entire mod-loading phase.
unless defined?(LonaPerformance::VERSION)
module LonaPerformance
  VERSION='0.1.14'
  ROOT=File.dirname(__FILE__)
  LEGACY_FILES=['60000_RGSSPerformancePatch.rb','60010_RGSSCombatPerformance.rb','60020_RGSSCombatGCExperiment.rb']
  class << self
    attr_reader :error, :status
  end

  def self.read_script(name)
    path=ROOT+'/'+name
    eval(File.read(path),TOPLEVEL_BINDING,path)
  end

  def self.validate_settings
    [SCALAR_GEOMETRY,NATIVE_GEOMETRY,EVENT_DISPATCH].each do |value|
      raise 'Optimization switches must be true or false' unless value==true || value==false
    end
    raise 'GC_BATCH_FRAMES must be 0, 16 or 30' unless [0,16,30].include?(GC_BATCH_FRAMES) && GC_BATCH_FRAMES.is_a?(Integer)
  end

  def self.preflight
    LEGACY_FILES.each do |name|
      raise "Remove legacy ModScripts/#{name} before enabling Lona Performance" if File.file?('ModScripts/'+name)
    end
    ['RGSSPerformancePatch','RGSSCombatPerformance','RGSSCombatGC'].each do |name|
      raise "Another performance patch already defined #{name}; restart without the legacy patches" if Object.const_defined?(name)
    end
  end

  def self.free_combat_support
    return {'state'=>'absent','supported'=>false} unless defined?(FreeCombatPrototype)
    path='ModScripts/_Mods/FreeCombatPrototype/_ModInfo.json'
    info=File.file?(path) ? JSON.decode(File.read(path)) : nil
    version=info.is_a?(Hash) ? info['version'] : nil
    required=['World','MapWorld','MapNPCs','MapMode','NativeEffects']
    supported=['0.7.1','0.7.2','0.8.0','0.8.1','0.8.2','0.8.3','0.8.4','0.8.5','0.8.6','0.8.7','0.8.8','0.8.9','0.8.10','0.8.11','0.8.12'].include?(version) &&
      required.all? { |name| FreeCombatPrototype.const_defined?(name) } && defined?(Scene_FreeCombatMap)
    if supported
      supported=FreeCombatPrototype::World.method_defined?(:segment_hits_rect?) &&
        [:blocked?,:clear_line?,:collision_walls].all? { |name| FreeCombatPrototype::MapWorld.method_defined?(name) } &&
        FreeCombatPrototype::MapMode.respond_to?(:active?) && FreeCombatPrototype::MapMode.respond_to?(:enabled?) && FreeCombatPrototype::MapMode.respond_to?(:session) &&
        FreeCombatPrototype::NativeEffects.respond_to?(:current) && defined?(Game_Event) &&
        [:fcp_npc_controller,:npc_original_update,:fcp_original_update].all? { |name| Game_Event.method_defined?(name) }
    end
    {'state'=>supported ? 'supported' : 'unsupported','supported'=>!!supported,'version'=>version}
  rescue StandardError => error
    {'state'=>'unsupported','supported'=>false,'reason'=>error.message}
  end

  def self.install
    return if @installed || @attempted
    @attempted=true
    begin
      preflight
      read_script('settings.rb')
      validate_settings
      compatibility=free_combat_support
      supported=compatibility['supported']
      if supported
        read_script('modules/scalar.rb')
        Object.const_set(:RGSSCombatPerformance,Module.new)
        RGSSCombatPerformance.const_set(:DLL_PATH,ROOT+'/native/geometry-x86.dll')
        read_script('modules/native.rb')
        RGSSPerformancePatch.segment_slabs=SCALAR_GEOMETRY
        RGSSCombatPerformance.native_geometry=NATIVE_GEOMETRY
        RGSSCombatPerformance.dispatch_gates=EVENT_DISPATCH
      end
      Object.const_set(:RGSSCombatGC,Module.new)
      RGSSCombatGC.const_set(:FREE_COMBAT_SUPPORTED,supported)
      read_script('modules/gc.rb')
      RGSSCombatGC.interval=GC_BATCH_FRAMES==0 ? 16 : GC_BATCH_FRAMES
      RGSSCombatGC.enabled=GC_BATCH_FRAMES!=0 && compatibility['state']!='unsupported'
      @status={
        'version'=>VERSION,
        'free_combat'=>compatibility,
        'scalar_hook'=>supported && FreeCombatPrototype::World.method_defined?(:rgss_performance_original_segment_hits_rect?),
        'native_hook'=>supported && FreeCombatPrototype::MapWorld.method_defined?(:perf_combat_original_blocked?),
        'native_library'=>supported && !!RGSSCombatPerformance.kernel,
        'dispatch_hook'=>supported && Game_Event.method_defined?(:perf_combat_original_controller),
        'gc_batch_frames'=>RGSSCombatGC.enabled ? GC_BATCH_FRAMES : 0
      }
      @installed=true
      prp "Lona Performance #{VERSION} Early Access: #{@status.inspect}; manual validation pending"
    rescue StandardError, LoadError, SyntaxError => error
      @error=error.message
      @status={'version'=>VERSION,'error'=>@error}
      RGSSCombatGC.release if defined?(RGSSCombatGC)
      if defined?($mod_manager) && $mod_manager && $mod_manager['LonaPerformance']
        $mod_manager['LonaPerformance'].error=@error
      end
      prp "Lona Performance #{VERSION}: #{@error}"
    end
  end
end

# Install optional integration hooks after every addon has loaded.
class << SceneManager
  alias_method :lona_performance_original_run, :run
  def run
    LonaPerformance.install
    lona_performance_original_run
  end
end
end
