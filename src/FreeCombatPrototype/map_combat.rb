module FreeCombatPrototype
  # Actors delegate to native combat whenever they are outside the active continuous controller.
  module ContinuousSkills
    def apply_stun_effect(state_id)
      return super unless fcp_free_actor? && respond_to?(:npc_name) && npc_name == 'UniqueFishkindFistMasterT2'
      # Native T2 mistakenly shares the stun duration (initially nil) with its resistance counter.
      @fcp_stun_cover_count = (@fcp_stun_cover_count || 0) + 1
      return if @fcp_stun_cover_count < 3
      @fcp_stun_cover_count = 0
      Battle_System.instance_method(:apply_stun_effect).bind(self).call(state_id)
    end

    def fcp_free_actor?
      return false unless MapMode.active? && @fcp_combat.equal?(MapMode.session.combat)
      return true if map_token.equal?($game_player)
      return @fcp_combat.npcs.registered?(map_token) if @fcp_combat.respond_to?(:npcs) && @fcp_combat.npcs
      map_token.equal?(MapMode.session.opponent)
    end

    def direction
      # A native bunker stair reads player.actor.direction instead of player.direction.
      return map_token.direction if fcp_free_actor? && map_token.equal?($game_player)
      super
    end

    def launch_skill(skill, force = false)
      if fcp_free_actor?
        followup = NativeEffects.scripted && NativeEffects.current(NativeEffects.source)
        return false unless followup || @fcp_combat.can_launch?(self)
        missing = [skill.summon_user, skill.summon_hit, skill.summon_hold].compact.reject { |name| $data_EventLib[name] } if skill
        unless missing.nil? || missing.empty?
          @fcp_combat.missing_effect(missing.first)
          return false
        end
      end
      @fcp_combat.npcs.face_target(map_token) if fcp_free_actor? && @fcp_combat.respond_to?(:npcs) && @fcp_combat.npcs && @fcp_combat.npcs.registered?(map_token)
      super
    end

    def process_skill_result(skill)
      return super unless fcp_free_actor?
      NativeEffects.with_source(map_token, false) { super }
    end

    def cancel_holding(release = false)
      skill = self.skill
      @fcp_combat.effects.capture_aim if release && fcp_free_actor?
      result = super
      if release && skill && skill.simply_holding? && fcp_free_actor?
        @fcp_combat.begin_recovery(self, skill)
      end
      result
    end

    def launch_effect_skill(skill)
      result = NativeEffects.with_source(map_token, false) { super }
      @fcp_combat.begin_recovery(self, skill) if fcp_free_actor?
      result
    end
  end

  class ActionRecovery
    def initialize
      @actions = {}
    end

    def begin_action(actor, skill)
      animation = actor.map_token.animation
      duration = animation ? animation.frames.inject(1) { |sum, frame| sum + [frame[2], 1].max } : [skill.hit_frame.to_i, 1].max
      @actions[actor.object_id] = [actor, duration]
      duration
    end

    def busy?(actor)
      @actions.has_key?(actor.object_id)
    end

    def update
      @actions.delete_if do |key, (actor, remaining)|
        animation = actor.map_token.animation
        remaining = [remaining, animation.frames.inject(1) { |sum, frame| sum + [frame[2], 1].max }].max if animation
        remaining -= 1 unless actor.map_token.animation || actor.action_state == :skill
        @actions[key][1] = remaining
        remaining <= 0
      end
    end
  end

  NativeShot = Struct.new(:x, :y, :dx, :dy, :life, :source, :skill)

  class NativeCombat
    attr_reader :paused, :notice, :effects, :recovery
    def initialize(world, opponent)
      @world, @opponent = world, opponent
      @player = $game_player.actor
      @enemy = opponent && opponent.actor
      @held = {}
      @recovery = ActionRecovery.new
      @effects = NativeEffects.new(self, world, opponent)
      @paused = true
      @notice = 'Space: start / pause combat'
      [@player, @enemy].compact.each do |actor|
        actor.extend(ContinuousSkills)
        actor.instance_variable_set(:@fcp_combat, self)
      end
      sync_health
    end

    def selected_skill(type)
      @player.usable_skills.find { |skill| skill.type == type }
    end

    def sync_health
      [[@player, @world.player], [@enemy, @world.enemy]].each do |actor, body|
        next unless actor
        body.hp = actor.health > 0 && actor.sta > -100 && actor.action_state != :death ? actor.health : 0
      end
    end

    def available?(actor)
      actor.health > 0 && actor.sta > -100 && ![:death, :stun, :sex, :grabbed, :grabber].include?(actor.action_state)
    end

    def missing_effect(name)
      @notice = "Missing native effect: #{name}"
    end

    def can_launch?(actor)
      available?(actor) && actor.action_state != :skill && !@recovery.busy?(actor)
    end

    def begin_recovery(actor, skill)
      @recovery.begin_action(actor, skill)
    end

    def launch(actor, skill, key = nil)
      return unless skill && can_launch?(actor)
      unless actor.cost_affordable?(skill)
        @notice = "Insufficient resources: #{skill.name}"
        return
      end
      if actor.launch_skill(skill, true)
        @held[actor] = key if skill.holding?
        @notice = skill.name
      end
    end

    def update_actor(actor, keyboard)
      actor.update_state_frames
      actor.update_stun
      if actor.equal?(@player) && [:sex, :grabber, :grabbed].include?(actor.action_state)
        $game_player.update_action_state
        return
      end
      if actor.action_state == :skill
        actor.update_skill_eff
        $game_player.update_skill_holding if actor.equal?(@player) && !@held.has_key?(actor)
        if actor.skill && actor.skill.holding? && @held[actor]
          if actor.equal?(@player) && $game_player.checkHoldCancel
            actor.process_skill_cost_reverse(actor.skill)
            SndLib.sound_equip_armor(60,160)
            actor.cancel_holding(false)
            @held.delete(actor)
          elsif !keyboard.down?(@held[actor])
            actor.cancel_holding(true)
            @held.delete(actor)
          end
        end
      else
        @held.delete(actor)
      end
    end

    def update_pause(keyboard)
      return if @pause_input_frame == Graphics.frame_count
      @pause_input_frame = Graphics.frame_count
      if keyboard.trigger?(:space)
        @paused = !@paused
      end
    end

    def update(dx, dy, keyboard)
      update_pause(keyboard)
      return if @paused
      @recovery.update
      @effects.prune
      (@npcs ? [@player] : [@player, @enemy]).each { |actor| update_actor(actor, keyboard) }
      unless $game_player.animation
        idle_frames = $game_player.instance_variable_get(:@afk_count).to_i + 1
        $game_player.instance_variable_set(:@afk_count, idle_frames >= 60 ? 0 : idle_frames)
        $game_player.handle_on_move_fps_update if idle_frames >= 60
      end
      $game_player.process_rule_movement_update
      sync_health
      dx, dy = @effects.update_selector(dx, dy)
      length = Math.sqrt(dx * dx + dy * dy)
      if length > 0 && available?(@player) && @player.action_state != :skill && (!MapMode.story? || !$game_player.process_rule_movable?)
        @world.player.facing_x, @world.player.facing_y = dx / length, dy / length
        speed = $game_player.distance_per_frame * 32
        @world.move(@world.player, dx / length * speed, dy / length * speed)
      end
      [['normal', :melee], ['heavy', :heavy], ['control', :control]].each do |type, key|
        next unless keyboard.trigger?(key)
        record = selected_skill(type)
        launch(@player, record && $data_arpgskills[record.type_tag], key)
      end
      if keyboard.trigger?(:shoot)
        record = selected_skill('normal')
        skill = record && $data_arpgskills[record.type_tag]
        if skill && skill.is_projectile?
          launch(@player, skill, :shoot)
        else
          @notice = 'Equip a ranged weapon before shooting'
        end
      end
      unless keyboard.trigger?(:mainhand) || keyboard.trigger?(:offhand) || keyboard.trigger?(:menu)
        $game_player.update_skill_input if can_launch?(@player)
      end
      $game_player.update_dodge
      update_enemy if @world.alive?(@world.enemy) && @world.alive?(@world.player)
      sync_health
    end

    def update_enemy
      return if @npcs
      return unless can_launch?(@enemy)
      dx, dy = @world.player.x - @world.enemy.x, @world.player.y - @world.enemy.y
      length = Math.sqrt(dx * dx + dy * dy)
      if length > 0
        @world.enemy.facing_x, @world.enemy.facing_y = dx / length, dy / length
      end
      skill = @enemy.skills_killer.find { |s| !s.is_projectile? && !s.effect.empty? && !s.holding? }
      return unless skill
      if in_melee_range?(@world.enemy, @world.player, skill)
        @opponent.set_direction(dx.abs > dy.abs ? (dx > 0 ? 6 : 4) : (dy > 0 ? 2 : 8))
        launch(@enemy, skill)
      elsif point = @world.enemy_destination
        dx, dy = point[0] - @world.enemy.x, point[1] - @world.enemy.y
        length = Math.sqrt(dx * dx + dy * dy)
        speed = [2.0 ** @enemy.move_speed / 8.0, length].min
        @world.move(@world.enemy, dx / length * speed, dy / length * speed) if length > 0
      end
    end

    def in_melee_range?(body, target, skill)
      dx, dy = target.x - body.x, target.y - body.y
      length = Math.sqrt(dx * dx + dy * dy)
      # AI only estimates when to start; native sensor masks determine actual hits.
      length <= skill.range * 32 + target.radius &&
        (length == 0 || (dx * body.facing_x + dy * body.facing_y) / length >= 0.5) &&
        @world.clear_line?(body.x, body.y, target.x, target.y)
    end

  end
end
