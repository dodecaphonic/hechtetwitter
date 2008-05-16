require 'configuration'

class Credentials
  def initialize
    @xml = GladeXML.new('lib/twitter.glade', 'credentials') { |m| method(m) }
    @window = @xml['credentials']
    #define_behavior
    @window.show_all
  end

  def define_behavior
    @xml['ok'].signal_connect('clicked') &method(:on_ok_clicked)
    @xml['cancel'].signal_connect('clicked') &method(:on_cancel_clicked)
  end

  def on_cancel_clicked(button)
    Gtk.main_quit
  end

  def on_ok_clicked(button)
    ue, pe   = @xml['username'], @xml['password']
    username = ue.text.strip
    password = pe.text.strip

    if username.empty? || password.empty?
      ue.select_region 0, -1
      ue.grab_focus
    else
      credentials = TwitterCredentials.new username, password
      state       = SavedState.create credentials
      state.take_snapshot
      @window.destroy
      HechteTwitter.new state
    end
  end

  def on_credentials_delete_event(w, e)
    w.destroy
    Gtk.main_quit
  end
end
