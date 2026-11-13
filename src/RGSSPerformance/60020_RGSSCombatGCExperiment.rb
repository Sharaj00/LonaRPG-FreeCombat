# Experimental: delayed finalizers can affect other mods. Disabled by default.
module RGSSCombatGC
  class << self
    attr_accessor :enabled, :interval
    attr_reader :stats
  end
  self.enabled=false
  self.interval=30
  MAX_PRIVATE=768*1024*1024
  MAX_GROWTH=32*1024*1024
  @owned=false
  @frames=0
  @stats={'collections'=>0,'memory_releases'=>0,'peak_private_bytes'=>0}
  begin
    @memory=Win32API.new('psapi','GetProcessMemoryInfo','lpl','i')
    @buffer=([44]+[0]*10).pack('L11')
  rescue StandardError, LoadError
    @memory=nil
  end
  def self.private_bytes
    return nil unless @memory && @memory.call(-1,@buffer,44)!=0
    @buffer.unpack('L11')[10]
  end
  def self.release
    return unless @owned
    @owned=false
    @frames=0
    GC.enable
  end
  def self.eligible?(scene)
    return false unless enabled && interval.is_a?(Integer) && interval.between?(1,30)
    free_combat=const_defined?(:FREE_COMBAT_SUPPORTED) ? FREE_COMBAT_SUPPORTED : !!defined?(FreeCombatPrototype::MapMode)
    if free_combat
      mode=FreeCombatPrototype::MapMode
      if mode.enabled?
        return mode.active? && !mode.session.suspended? && !mode.session.combat.paused
      end
    end
    return false unless defined?(Scene_Map) && scene.is_a?(Scene_Map)
    return false unless $game_map && $game_map.interpreter && $game_player && $game_message
    !$game_pause && !$game_map.interpreter.running? && !$game_message.busy? && !$game_message.visible &&
      !$game_player.cannot_control && !$game_player.jumping? && !$game_player.instance_variable_get(:@move_route_forcing) &&
      (!$game_player.respond_to?(:force_update) || $game_player.force_update!=false)
  end
  def self.update_frame(scene)
    eligible=eligible?(scene)
    memory=eligible && private_bytes
    @stats['peak_private_bytes']=[@stats['peak_private_bytes'],memory].max if memory
    unless eligible && memory && memory<MAX_PRIVATE
      release
      return yield
    end
    unless @owned
      return yield if GC.disable # Respect a collector disabled by another script.
      @owned=true
      @baseline=memory
      @frames=0
    end
    completed=false
    begin
      result=yield
      @frames+=1
      memory=private_bytes
      if !memory || memory>=MAX_PRIVATE || !SceneManager.scene.equal?(scene) || !eligible?(scene)
        @stats['memory_releases']+=1 if !memory || memory>=MAX_PRIVATE
        release
      elsif @frames>=interval || memory-@baseline>=MAX_GROWTH
        GC.enable
        GC.start
        @stats['collections']+=1
        GC.disable
        @baseline=private_bytes || memory
        @frames=0
      end
      completed=true
      result
    ensure
      release unless completed
    end
  rescue Exception
    release
    raise
  end
  def self.update(scene)
    return yield if @inside_update
    @inside_update=true
    begin
      update_frame(scene) { yield }
    ensure
      @inside_update=false
    end
  end
  def self.attach(target)
    original=target.instance_method(:update)
    target.send(:define_method,:update) do
      RGSSCombatGC.update(self) { original.bind(self).call }
    end
  end
end
targets=[]
targets << Scene_Map if defined?(Scene_Map)
targets << Scene_FreeCombatMap if defined?(Scene_FreeCombatMap)
targets.each do |target|
  RGSSCombatGC.attach(target)
end
