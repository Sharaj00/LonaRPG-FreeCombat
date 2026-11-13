module FreeCombatPrototype
  Shot = Struct.new(:x, :y, :dx, :dy, :life)
  class World
    attr_reader :shots, :swing_frames
    def initialize
      @walls = [[0, 64, 544, 16], [0, 400, 544, 16],
                [0, 64, 16, 352], [528, 64, 16, 352],
                [248, 152, 32, 120], [112, 304, 112, 24]]
      @player = Body.new(96.0, 192.0, 10.0, 100, 1.0, 0.0, 0)
      @enemy = Body.new(432.0, 192.0, 11.0, 100, -1.0, 0.0, 0)
      @shots = []
      @swing_frames = 0
      @shot_cooldown = 0
    end

    def melee
      return if @player.cooldown > 0 || !alive?(@player)
      @player.cooldown = 24
      @swing_frames = 8
      dx = @enemy.x - @player.x
      dy = @enemy.y - @player.y
      distance = Math.sqrt(dx * dx + dy * dy)
      return unless alive?(@enemy) && distance <= 46 + @enemy.radius
      return if distance > 0 && (dx * @player.facing_x + dy * @player.facing_y) / distance < 0.5
      @enemy.hp = [@enemy.hp - 25, 0].max if clear_line?(@player.x, @player.y, @enemy.x, @enemy.y)
    end

    def fire
      return if @shot_cooldown > 0 || !alive?(@player)
      @shot_cooldown = 20
      @shots << Shot.new(@player.x, @player.y, @player.facing_x * 8,
                        @player.facing_y * 8, 90)
    end

    def update_shots
      @shots.delete_if do |shot|
        shot.life -= 1
        stopped = false
        steps = [(Math.sqrt(shot.dx ** 2 + shot.dy ** 2) / 2.0).ceil, 1].max
        steps.times do
          shot.x += shot.dx / steps
          shot.y += shot.dy / steps
          if blocked?(shot.x, shot.y, 4)
            stopped = true
          elsif alive?(@enemy) && (shot.x - @enemy.x) ** 2 + (shot.y - @enemy.y) ** 2 <= (@enemy.radius + 4) ** 2
            @enemy.hp = [@enemy.hp - 20, 0].max
            stopped = true
          end
          break if stopped
        end
        stopped || shot.life <= 0
      end
    end

    def encounter_running?
      alive?(@player) && alive?(@enemy)
    end

    def update(dx, dy, attack = false, shoot = false)
      return unless encounter_running?
      [@player, @enemy].each { |body| body.cooldown -= 1 if body.cooldown > 0 }
      @shot_cooldown -= 1 if @shot_cooldown > 0
      @swing_frames -= 1 if @swing_frames > 0
      length = Math.sqrt(dx * dx + dy * dy)
      if length > 0
        @player.facing_x, @player.facing_y = dx / length, dy / length
        move(@player, dx / length * 2.6, dy / length * 2.6)
      end
      melee if attack
      fire if shoot
      update_shots
      return unless alive?(@enemy)
      ex = @player.x - @enemy.x
      ey = @player.y - @enemy.y
      distance = Math.sqrt(ex * ex + ey * ey)
      if distance <= 29 && clear_line?(@enemy.x, @enemy.y, @player.x, @player.y)
        if @enemy.cooldown <= 0
          @player.hp = [@player.hp - 10, 0].max
          @enemy.cooldown = 45
        end
      elsif destination = enemy_destination
        dx, dy = destination[0] - @enemy.x, destination[1] - @enemy.y
        length = Math.sqrt(dx * dx + dy * dy)
        speed = [1.35, length].min
        move(@enemy, dx / length * speed, dy / length * speed) if length > 0
      end
    end
  end
end
