# All optional combat records share the recorder's bounded, failure-tolerant journal.
class FreeCombatPrototype::NativeCombat
  alias_method :fcd_journal_launch, :launch
  def launch(actor, skill, key = nil)
    result = fcd_journal_launch(actor, skill, key)
    FreeCombatDiagnostics.emit('combat_action', {'actor'=>actor.npc_name,
      'skill'=>skill && skill.name, 'state'=>actor.action_state.to_s,
      'health'=>actor.health, 'sta'=>actor.sta}) if skill
    result
  end

  alias_method :fcd_journal_pause, :update_pause
  def update_pause(keyboard)
    before = paused
    result = fcd_journal_pause(keyboard)
    FreeCombatDiagnostics.emit('combat_pause', {'paused'=>paused}) if paused != before
    result
  end
end
