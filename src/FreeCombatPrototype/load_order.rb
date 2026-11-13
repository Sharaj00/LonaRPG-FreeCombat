# Ruby 1.9 / RGSS301. No addon scripts are executed by this planner.
module FreeCombatPrototype
  module LoadOrder
    ORDER = %w[RolePlayS _GrayRat_CustomNPCchs _LoliMama_CustomNPCchs
      _Milo_CustomNPCchs _Musketeer_CustomNPCchs DedGirl_chs OrkindSlayerGirl_chs
      LonaRpgCoockingExpanded temper_trine LonaRPG_FactionClashes
      LonaRPG_RestJournal PassiveStaminaRegen FreeCombatPrototype
      FreeCombatCompatibility FreeCombatDiagnostics LonaPerformance]

    def self.plan(mods, enabled)
      ids = mods.map { |mod| mod.id }
      edges = Hash.new { |hash, key| hash[key] = [] }
      connect = lambda do |left, right|
        edges[left] << right if left != right && ids.include?(right) && !edges[left].include?(right)
      end
      known = ORDER.select { |id| ids.include?(id) && enabled.include?(id) }
      known.each_cons(2) { |left, right| connect.call(left, right) }
      # Preserve the relative order of all disabled/unmanaged addons.
      other = ids.reject { |id| known.include?(id) }
      other.each_cons(2) { |left, right| connect.call(left, right) }
      mods.each do |mod|
        mod.before.each { |id| connect.call(mod.id, id) }
        if enabled.include?(mod.id)
          mod.requires.each_key do |id|
            connect.call(id, mod.id) if ids.include?(id) && enabled.include?(id)
          end
        end
      end
      result, remaining = [], ids.dup
      until remaining.empty?
        next_id = remaining.find { |id| remaining.none? { |source| edges[source].include?(id) } }
        raise 'Conflicting addon load-order rules: ' + remaining.join(', ') unless next_id
        result << next_id
        remaining.delete(next_id)
      end
      result.map { |id| mods.find { |mod| mod.id == id } }
    end

    def self.notice(message)
      msgbox(message)
    end

    def self.apply(manager, path)
      mods, ini = manager.load_order, manager.mods_ini
      enabled = mods.select { |mod| ini[File.basename(mod.path)]['Banned'] == 0 }.map { |mod| mod.id }
      desired = plan(mods, enabled)
      return if desired.map { |mod| mod.id } == mods.map { |mod| mod.id }
      original = File.open(path, 'rb') { |file| file.read }
      backup = path + '.free-combat-order.bak'
      File.open(backup, 'wb') { |file| file.write(original) }
      begin
        # Do not use save_ini: it also writes runtime error/enable flags.
        desired.each_with_index { |mod, index| ini[File.basename(mod.path)]['LoadOrder'] = index }
        ini.write
      rescue StandardError
        File.open(path, 'wb') { |file| file.write(original) }
        raise
      end
      notice('Free Combat configured the supported addon load order. Restart the game once to apply it. No addon was enabled. Previous settings: ' + backup)
      exit
    rescue StandardError => error
      notice('Free Combat could not configure addon load order. Startup stopped; resolve the reported conflict before playing. ' + error.message)
      exit
    end
  end
end
