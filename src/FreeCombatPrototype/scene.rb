module FreeCombatPrototype
  # Native RGSS input reports phantom directions on this runtime; isolate continuous input.
  class Keyboard
    KEYS = {:menu => 0x4D, :mainhand => 0x21, :offhand => 0x22, :heavy => 0x43, :control => 0x56, :left => 0x25, :up => 0x26, :right => 0x27, :down => 0x28,
            :melee => 0x5A, :enter => 0x0D, :space => 0x20, :shoot => 0x10,
            :interact => 0x45, :cancel => 0x58}
    MOVEMENT_KEYS = {:left => :LEFT, :up => :UP, :right => :RIGHT, :down => :DOWN}

    def initialize
      @key_state = Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
      @foreground = Win32API.new('user32', 'GetForegroundWindow', '', 'l')
      @active = Win32API.new('user32', 'GetActiveWindow', '', 'l')
      @current, @previous = [], []
    end

    def focused?
      window = @active.call
      window != 0 && window == @foreground.call
    end

    def held?(code)
      (@key_state.call(code) & 0x8000) != 0
    end

    def update
      @previous = @current
      @current = []
      return unless focused?
      KEYS.each do |key, fallback|
        direction = MOVEMENT_KEYS[key]
        codes = direction && defined?(Input::SYM_KEYS) ? Input::SYM_KEYS[direction] : [fallback]
        @current << key if Array(codes).any? { |code| code.is_a?(Integer) && code > 0 && code < 256 && held?(code) }
      end
    end

    def down?(key)
      @current.include?(key)
    end

    def trigger?(key)
      down?(key) && !@previous.include?(key)
    end
  end
end
