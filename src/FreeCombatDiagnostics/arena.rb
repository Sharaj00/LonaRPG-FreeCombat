module FreeCombatPrototype
  Keyboard::KEYS.merge!(:weapon => 0x09, :reset => 0x74, :exit => 0x1B)
  class Arena
    attr_reader :world

    def initialize
      @world = World.new
    end

    def create_display
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 1000000
      @sprite = Sprite.new(@viewport)
      @sprite.bitmap = Bitmap.new(World::WIDTH, World::HEIGHT)
      scale = [1.0, Graphics.width.to_f / World::WIDTH, Graphics.height.to_f / World::HEIGHT].min
      @sprite.zoom_x = @sprite.zoom_y = scale
      @sprite.x = ((Graphics.width - World::WIDTH * scale) / 2).round
      @sprite.y = ((Graphics.height - World::HEIGHT * scale) / 2).round
      @background = Sprite.new(@viewport)
      @background.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @background.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(12, 17, 25))
      @background.z = -1
    end

    def dispose
      [@sprite, @background].each do |sprite|
        next unless sprite
        sprite.bitmap.dispose if sprite.bitmap && !sprite.bitmap.disposed?
        sprite.dispose unless sprite.disposed?
      end
      @viewport.dispose if @viewport
      @viewport = nil
    end

    def run
      previous_rate = Graphics.frame_rate
      begin
        Graphics.frame_rate = 60
        create_display
        Graphics.transition(0)
        keyboard = Keyboard.new
        keyboard.update
        loop do
          Graphics.update
          Input.update
          keyboard.update
          break if keyboard.trigger?(:exit) || keyboard.trigger?(:cancel)
          @world = World.new if keyboard.trigger?(:reset)
          dx = (keyboard.down?(:right) ? 1 : 0) - (keyboard.down?(:left) ? 1 : 0)
          dy = (keyboard.down?(:down) ? 1 : 0) - (keyboard.down?(:up) ? 1 : 0)
          attack = [:melee, :enter, :space].any? { |key| keyboard.trigger?(key) }
          @world.update(dx, dy, attack, keyboard.trigger?(:shoot))
          render
        end
      ensure
        dispose
        Graphics.frame_rate = previous_rate
        Input.update
      end
    end

    def rectangle(bitmap, x, y, width, height, color)
      bitmap.fill_rect(x.round, y.round, width, height, Color.new(*color))
    end

    def draw_body(bitmap, body, color)
      return unless @world.alive?(body)
      r = body.radius.to_i
      rectangle(bitmap, body.x - r, body.y - r, r * 2, r * 2, color)
      rectangle(bitmap, body.x - 15, body.y - r - 9, 30, 4, [58, 66, 78])
      rectangle(bitmap, body.x - 15, body.y - r - 9, (body.hp * 0.3).round, 4, [104, 229, 153])
    end

    def render
      bitmap = @sprite.bitmap
      bitmap.fill_rect(0, 0, World::WIDTH, World::HEIGHT, Color.new(20, 28, 39))
      bitmap.font.size = 18
      bitmap.font.color = Color.new(232, 238, 246)
      bitmap.draw_text(16, 0, 512, 24, 'FREE COMBAT / isolated prototype')
      bitmap.font.size = 15
      bitmap.draw_text(16, 23, 520, 20, 'Move: game bindings   Z/Enter: melee   Shift: shoot')
      bitmap.draw_text(16, 42, 520, 20, 'F5: reset   X/Esc: exit   Blue: player   Red: enemy')
      @world.walls.each { |wall| rectangle(bitmap, *wall, [71, 88, 109]) }
      if @world.swing_frames > 0
        p = @world.player
        rectangle(bitmap, p.x + p.facing_x * 32 - 9, p.y + p.facing_y * 32 - 9, 18, 18, [244, 200, 98])
      end
      draw_body(bitmap, @world.player, [83, 177, 242])
      draw_body(bitmap, @world.enemy, [231, 100, 112])
      @world.shots.each { |shot| rectangle(bitmap, shot.x - 4, shot.y - 4, 8, 8, [157, 225, 255]) }
      unless @world.alive?(@world.player) && @world.alive?(@world.enemy)
        bitmap.font.size = 24
        message = @world.alive?(@world.player) ? 'Enemy defeated - F5 to reset' : 'Player defeated - F5 to reset'
        bitmap.draw_text(16, 340, 512, 40, message, 1)
      end
    end
  end
end
