# Test-only hook before 500_Mod_loader.rb, in the private compatibility runner.
$fcp_order_ini_before = File.open('UserData/GameMods.ini','rb') { |file| file.read }
module Kernel
  alias_method :fcp_order_test_msgbox, :msgbox
  def msgbox(*messages)
    message=messages.join(' ')
    return fcp_order_test_msgbox(*messages) unless message.start_with?('Free Combat ')
    File.open('load-order-notice.txt','w') { |file| file.write(message) }
    File.open('load-order-before.ini','wb') { |file| file.write($fcp_order_ini_before) }
  end
end
