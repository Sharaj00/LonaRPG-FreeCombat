# Restart the game after editing. Each optimization can be disabled independently.
module LonaPerformance
  SCALAR_GEOMETRY = true
  NATIVE_GEOMETRY = true
  EVENT_DISPATCH = true
  # Experimental: delayed finalizers can affect mods. 0 = off; try 16 or 30 only in a test copy.
  GC_BATCH_FRAMES = 0
end
