# Focused RGSS checks at the physical-key/native-binding seam.
module MovementBindingChecks
  def self.check(name, result)
    @lines << "#{result ? 'PASS' : 'FAIL'}: #{name}"
    File.open('movement-binding-verification.txt', 'w') { |file| file.puts(@lines) }
    raise name unless result
  end

  def self.run
    @lines = []
    had_bindings = Input.const_defined?(:SYM_KEYS)
    original = Input::SYM_KEYS if had_bindings
    Input.send(:remove_const, :SYM_KEYS) if had_bindings
    mappings = {:UP=>[0x57,0,0], :DOWN=>[0x53,0,0], :LEFT=>[0x41,0,0], :RIGHT=>[0x44,0,0]}
    Input.const_set(:SYM_KEYS, mappings)
    keyboard = FreeCombatPrototype::Keyboard.new
    keyboard.instance_variable_set(:@keys, [])
    keyboard.instance_variable_set(:@focus, true)
    def keyboard.held?(code); @keys.include?(code); end
    def keyboard.focused?; @focus; end
    {:up=>0x57, :down=>0x53, :left=>0x41, :right=>0x44}.each do |direction, code|
      keyboard.instance_variable_set(:@keys, [code])
      keyboard.update
      check("WASD #{direction} follows native mapping", keyboard.down?(direction))
    end
    keyboard.instance_variable_set(:@keys, [0x25,0x26,0x27,0x28])
    keyboard.update
    check('replaced arrows do not move', [:up,:down,:left,:right].none? { |key| keyboard.down?(key) })
    mappings[:RIGHT] = [0x44,0x27,0x66]
    [0x44,0x27,0x66].each do |code|
      keyboard.instance_variable_set(:@keys, [code])
      keyboard.update
      check("secondary/tertiary movement binding #{code} works", keyboard.down?(:right))
    end
    mappings[:RIGHT] = [0x4C,0,0]
    keyboard.instance_variable_set(:@keys, [0x44,0x27])
    keyboard.update
    check('live reassignment removes previous bindings', !keyboard.down?(:right))
    keyboard.instance_variable_set(:@keys, [0x4C])
    keyboard.update
    check('live reassignment uses new binding without restart', keyboard.down?(:right))
    mappings[:RIGHT] = [0,nil,-1]
    keyboard.instance_variable_set(:@keys, [0,0x27])
    keyboard.update
    check('unbound and placeholder keys do not fall back to arrows', !keyboard.down?(:right))
    mappings[:RIGHT] = nil
    keyboard.update
    check('nil native binding remains unbound', !keyboard.down?(:right))
    mappings.delete(:RIGHT)
    keyboard.update
    check('missing native binding remains unbound', !keyboard.down?(:right))
    mappings[:RIGHT] = [0x44]
    keyboard.instance_variable_set(:@keys, [0x44])
    keyboard.instance_variable_set(:@focus, false)
    keyboard.update
    check('unfocused remapped input is ignored', !keyboard.down?(:right))
    keyboard.instance_variable_set(:@focus, true)
    mappings.replace(:UP=>[0x26], :DOWN=>[0x28], :LEFT=>[0x25], :RIGHT=>[0x27])
    keyboard.instance_variable_set(:@keys, [0x27])
    keyboard.update
    check('reset native arrows work', keyboard.down?(:right))
    keyboard.instance_variable_set(:@keys, [0x57,0x41,0x53,0x44])
    keyboard.update
    check('reset removes WASD movement', [:up,:down,:left,:right].none? { |key| keyboard.down?(key) })
    Input.send(:remove_const, :SYM_KEYS)
    keyboard.instance_variable_set(:@keys, [0x26])
    keyboard.update
    check('minimal runner retains arrow fallback without native binding API', keyboard.down?(:up))
    @lines << "TOTAL: #{@lines.size} passed"
    File.open('movement-binding-verification.txt', 'w') { |file| file.puts(@lines) }
  ensure
    Input.send(:remove_const, :SYM_KEYS) if Input.const_defined?(:SYM_KEYS)
    Input.const_set(:SYM_KEYS, original) if had_bindings
  end
end
