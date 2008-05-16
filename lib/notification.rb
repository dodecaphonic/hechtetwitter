require 'rbus'
require 'gtk2'

class DesktopNotifier
  def initialize
    session_bus = RBus.session_bus
    notify    = session_bus.get_object 'org.freedesktop.Notifications', '/org/freedesktop/Notifications'
    @notifier = notify
    @enabled  = true
  end

  def notify(message)
    if @enabled
      @notifier.Notify 'HechteTwitter', message.id, nil, message.user.screen_name, message.text, [], {}, -1
    end
  end

  def enabled?
    @enabled
  end

  def enable(which=true)
    @enabled = which
  end

  def disable!
    enable false
  end
end
