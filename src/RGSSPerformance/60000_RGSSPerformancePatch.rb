# LonaRPG B.0.10.7.5.18 / FreeCombatPrototype 0.7.1-0.7.2 / RGSS3.
# Load after 500_Mod_loader.rb. Restart to remove; no save objects are changed.
module RGSSPerformancePatch
  class << self
    attr_accessor :segment_slabs
  end
  self.segment_slabs = true unless instance_variable_defined?(:@segment_slabs)
end

if defined?(FreeCombatPrototype::World) && FreeCombatPrototype::World.method_defined?(:segment_hits_rect?) && !FreeCombatPrototype::World.method_defined?(:rgss_performance_original_segment_hits_rect?)
  klass = FreeCombatPrototype::World
  original = klass.instance_method(:segment_hits_rect?)
  location = original.source_location
  info_path = 'ModScripts/_Mods/FreeCombatPrototype/_ModInfo.json'
  info = File.file?(info_path) ? JSON.decode(File.read(info_path)) : {}
  if ['0.7.1','0.7.2','0.8.0','0.8.1','0.8.2','0.8.3','0.8.4','0.8.5','0.8.6','0.8.7','0.8.8','0.8.9','0.8.10','0.8.11','0.8.12'].include?(info['version']) && original.arity == -9 && location && location[0].gsub('\\', '/').end_with?('/FreeCombatPrototype/core.rb')
    klass.class_eval do
      unless method_defined?(:rgss_performance_original_segment_hits_rect?)
        alias_method :rgss_performance_original_segment_hits_rect?, :segment_hits_rect?
        def segment_hits_rect?(x1, y1, x2, y2, left, top, width, height, open_edges = false)
          unless RGSSPerformancePatch.segment_slabs
            return rgss_performance_original_segment_hits_rect?(x1, y1, x2, y2, left, top, width, height, open_edges)
          end
          first, last = 0.0, 1.0
          dx, dy = x2 - x1, y2 - y1
          if dx == 0
            return false unless open_edges ? x1 > left && x1 < left + width : x1 >= left && x1 <= left + width
          else
            near, far = (left - x1).to_f / dx, (left + width - x1).to_f / dx
            near, far = far, near if near > far
            first = near if near > first
            last = far if far < last
            return false if open_edges ? first >= last : first > last
          end
          if dy == 0
            return false unless open_edges ? y1 > top && y1 < top + height : y1 >= top && y1 <= top + height
          else
            near, far = (top - y1).to_f / dy, (top + height - y1).to_f / dy
            near, far = far, near if near > far
            first = near if near > first
            last = far if far < last
            return false if open_edges ? first >= last : first > last
          end
          true
        end
      end
    end
  else
    prp 'RGSSPerformancePatch: unsupported or overridden collision method; skipped'
  end
end
