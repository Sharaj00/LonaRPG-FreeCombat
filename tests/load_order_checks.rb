# Standalone RGSS checks: no original game or player save is loaded.
module LoadOrderChecks
  Mod = Struct.new(:id, :path, :before, :requires)
  Manager = Struct.new(:load_order, :mods_ini)
  class Ini < Hash
    attr_accessor :path, :fail_write
    attr_reader :writes
    def write
      @writes = (@writes || 0) + 1
      File.open(path,'wb') { |file| file.write('partial') }
      raise IOError, 'injected write failure' if fail_write
      File.open(path,'wb') { |file| file.write(inspect) }
    end
  end
  @lines = []
  def self.check(name, result)
    raise 'FAIL: '+name unless result
    @lines << 'PASS: '+name
  end
  def self.mod(id)
    Mod.new(id,'ModScripts/_Mods/'+id,[],{})
  end
  def self.ids(result); result.map { |mod| mod.id }; end
  def self.run
    planner=FreeCombatPrototype::LoadOrder
    known=planner::ORDER.reject { |id| id=='FreeCombatCompatibility' }
    check('reversed supported set becomes canonical',ids(planner.plan(known.reverse.map { |id| mod(id) },known))==known)
    random=Random.new(1137)
    100.times do |i|
      selected=%w[RolePlayS PassiveStaminaRegen FreeCombatPrototype FreeCombatDiagnostics LonaPerformance]
      input=(selected+%w[OtherA OtherB OtherC temper_trine]).sort_by { random.rand }
      result=ids(planner.plan(input.map { |id| mod(id) },selected))
      check('known precedence '+i.to_s,result.select { |id| selected.include?(id) }==selected)
      check('unmanaged and disabled relative order '+i.to_s,
        result.reject { |id| selected.include?(id) }==input.reject { |id| selected.include?(id) })
    end
    core,role,other=mod('FreeCombatPrototype'),mod('RolePlayS'),mod('Other')
    other.before=['FreeCombatPrototype']
    check('native before rule remains authoritative',ids(planner.plan([core,other,role],[core.id,role.id,other.id]))==[other.id,role.id,core.id])
    other.before=[];other.requires={'FreeCombatPrototype'=>['==','0.8.11']}
    result=ids(planner.plan([other,core,role],[core.id,role.id,other.id]))
    check('enabled dependency precedes its consumer',result.index(core.id)<result.index(other.id))
    other.requires={'AbsentMod'=>['>=','1.0']}
    check('missing optional component is not invented',ids(planner.plan([other,core],[core.id,other.id])).sort==[core.id,other.id].sort)
    other.before=[role.id];role.before=[other.id]
    failed=false
    begin
      planner.plan([other,role,core],[core.id,role.id,other.id])
    rescue RuntimeError => error
      failed=error.message.include?('Conflicting')
    end
    check('contradictory metadata is rejected',failed)
    role.before=[]
    config=Ini.new;config.path='order-config.ini'
    config['RolePlayS']={'Banned'=>0,'LoadOrder'=>1,'CustomSetting'=>71}
    config['FreeCombatPrototype']={'Banned'=>0,'LoadOrder'=>0}
    config['UnrelatedSection']={'Value'=>'keep'}
    File.open(config.path,'wb') { |file| file.write('original bytes') }
    File.open('untouched-save.rvdata2','wb') { |file| file.write('private fixture') }
    # A failed native load may change mod.enabled, but persisted Banned is authoritative.
    [false,true].each do |failure|
      config.fail_write=failure
      File.open(config.path,'wb') { |file| file.write('original bytes') }
      begin
        planner.apply(Manager.new([core,role],config),config.path)
      rescue SystemExit
      end
      check('previous INI backed up '+failure.to_s,File.open(config.path+'.free-combat-order.bak','rb') { |file| file.read }=='original bytes')
      check('enable and custom settings preserved '+failure.to_s,config['RolePlayS']['Banned']==0 && config['RolePlayS']['CustomSetting']==71 && config['UnrelatedSection']['Value']=='keep')
      if failure
        check('failed write restores exact original bytes',File.open(config.path,'rb') { |file| file.read }=='original bytes')
      end
    end
    check('save file is never touched',File.open('untouched-save.rvdata2','rb') { |file| file.read }=='private fixture')
    before=config.writes
    planner.apply(Manager.new([role,core],config),config.path)
    check('correct order makes no write',config.writes==before)
    File.open('verification.txt','w') { |file| file.puts(@lines);file.puts("TOTAL: #{@lines.size} passed") }
    exit
  rescue StandardError, ScriptError => error
    File.open('failure.txt','w') { |file| file.puts(error.class,error.message,error.backtrace) }
    exit
  end
end
module FreeCombatPrototype::LoadOrder
  def self.notice(message); end
end
rgss_main { LoadOrderChecks.run }
