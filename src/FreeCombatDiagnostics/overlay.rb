module FreeCombatDiagnostics
  def self.overlay_visible?
    @overlay_visible == true
  end

  def self.toggle_overlay
    @overlay_visible = !overlay_visible?
  end
end

class Scene_FreeCombatMap
  alias_method :fcd_overlay_start, :start
  def start
    fcd_overlay_start
    @fcp_viewport = Viewport.new
    @fcp_viewport.z = 1000000
    @fcp_overlay = Sprite.new(@fcp_viewport)
    @fcp_overlay.bitmap = Bitmap.new(Graphics.width, 96)
    @fcp_effects = Sprite.new(@fcp_viewport)
    @fcp_effects.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @fcp_overlay.visible = false
    @fcp_effects.visible = false
  end

  alias_method :fcd_overlay_update, :update
  def update
    FreeCombatDiagnostics.toggle_overlay if Input.trigger?(:F9)
    fcd_overlay_update
    draw_fcp_overlay if SceneManager.scene.equal?(self)
  end

  def draw_fcp_overlay
    visible = FreeCombatDiagnostics.overlay_visible? && !$game_message.busy? && !$game_message.visible
    @fcp_overlay.visible = visible
    @fcp_effects.visible = false
    return unless visible
    mode = FreeCombatPrototype::MapMode
    lines = [mode.story? ? 'Story / Move: game bindings / Z normal / C heavy / V special / M menu' : 'Move: game bindings / Z normal / C heavy / V special / M menu / F8 exit']
    unless mode.active?
      status = $game_map.isOverMap ? 'Overworld: native tile movement' : 'waiting for native map events'
      lines << "Map #{$game_map.map_id}: #{status}." + (mode.test? ? ' F8 returns to title.' : '')
      refresh_fcp_hud(lines)
      return
    end
    session = mode.session
    world, combat = session.world, session.combat
    actor = $game_player.actor
    lines << "Map #{$game_map.map_id}  HP #{actor.health}  STA #{actor.sta}  #{combat.weapon_name}"
    lines << combat.skill_names
    outcome = !world.alive?(world.player) ? 'DEFEATED: health/exhaustion' : (combat.paused ? 'PAUSED' : 'LIVE')
    lines << (mode.story? ? "#{outcome} / Space pause / #{combat.notice}" : "#{outcome} / Space pause / Tab / PgUp main / PgDn off / #{combat.notice}")
    refresh_fcp_hud(lines)
    shots = combat.effects.instance_variable_get(:@projectiles).values.select do |shot|
      event = shot.source.map_token
      event.opacity == 0 || event.character_name.include?('debug_')
    end
    return if shots.empty?
    @fcp_effects.visible = true
    bitmap = @fcp_effects.bitmap
    bitmap.clear
    shots.each do |shot|
      x, y = shot.x - $game_map.display_x * 32, shot.y - $game_map.display_y * 32
      bitmap.fill_rect(x.round - 3, y.round - 3, 6, 6, Color.new(157, 225, 255))
    end

  end

  def refresh_fcp_hud(lines)
    return if lines == @fcp_hud_lines
    previous = @fcp_hud_lines || []
    bitmap = @fcp_overlay.bitmap
    bitmap.font.size = 16
    [previous.size, lines.size].max.times do |index|
      next if previous[index] == lines[index]
      bitmap.clear_rect(0, index * 24, Graphics.width, 24)
      next unless lines[index]
      bitmap.fill_rect(0, index * 24, Graphics.width, 24, Color.new(10, 14, 22, 210))
      bitmap.draw_text(8, index * 24, Graphics.width - 16, 24, lines[index])
    end
    @fcp_hud_lines = lines.dup
  end

  alias_method :fcd_overlay_terminate, :terminate
  def terminate
    @fcp_effects.bitmap.dispose if @fcp_effects
    @fcp_effects.dispose if @fcp_effects
    @fcp_overlay.bitmap.dispose if @fcp_overlay
    @fcp_overlay.dispose if @fcp_overlay
    @fcp_viewport.dispose if @fcp_viewport
    fcd_overlay_terminate
  end
end
