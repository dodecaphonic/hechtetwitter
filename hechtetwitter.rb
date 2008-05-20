#!/usr/bin/env ruby

$: << 'lib'
require 'rubygems'
require 'libglade2'
require 'gtk2'
require 'yaml'
require 'client/twitter'
require 'tweet_widget'
require 'twitter_credentials'
require 'notification'
require 'poller'
require 'credentials'

Thread.abort_on_exception = true

class HechteTwitter
  CHAR_LIMIT = 140
  ICON_LIST  = %w(ht16x16 ht32x32 ht48x48 ht64x64 ht128x128).map { |i| Gdk::Pixbuf.new "icons/#{i}.png" }
  
  def initialize(state)
    Gtk::Window.default_icon_list = ICON_LIST
    @maddie     = state
    @state      = state.system
    credentials = @state.credentials
#    ask_password(credentials) unless credentials.keep_password?
    @@spinner  = nil
    @xml       = GladeXML.new('lib/twitter.glade', 'twitter') { |m| method m }
    @tray      = define_tray_icon 
    @char_count = @xml['charCount']
    @tweets    = []
    @twitter   = Twitter::Client.new credentials.username, credentials.password
    @tips      = Gtk::Tooltips.new
    @xml['twitter'].title = "HechteTwitter - #{credentials.username}"
    @xml['twitter'].show_all
    @poller    = TimelinePoller.new(@twitter, :friends, 180) { |e| show_error e }
    @poller.add_observer self
    @notifier  = DesktopNotifier.new
    @poster    = nil
    change_timeline :friends
  end

  private
  # Defines a tray icon for the application.
  def define_tray_icon
    tray = Gtk::StatusIcon.new
    tray.pixbuf = ICON_LIST[2]
    tray.signal_connect('activate') do
      window = @xml['twitter']
      window.get_property('visible') ? window.hide : window.show
    end
    tray.signal_connect('popup_menu') do |w, b, t|
      menu = Gtk::Menu.new
      dnot = Gtk::CheckMenuItem.new 'Disable notifications'
      dnot.active = !@notifier.enabled?
      qopt = Gtk::MenuItem.new 'Quit HechteTwitter'
      qopt.signal_connect('activate') { quit }
      dnot.signal_connect('activate') do
        @notifier.enabled? ? @notifier.disable! : @notifier.enable
      end
      menu.append dnot
      menu.append Gtk::SeparatorMenuItem.new
      menu.append qopt
      menu.show_all
      x, y, push = w.position_menu(menu)
      menu.popup(nil, nil, b, t) { |m, mx, my, mp| [x, y] }
    end
    tray
  end

  # Hides window when closed.
  def on_twitter_delete_event(window, e)
    window.get_property('visible') ? window.hide : window.show
  end

  # Quits application -- destroys polling threads and kills Gtk's main thread.
  def quit
    @xml['twitter'].destroy    
    Gtk.main_quit
    @poller.stop
    @poster.join if @poster
    @maddie.take_snapshot
  end

  # Changes timeline currently being feched -- kills polling thread, changes
  # current state and starts polling the new one.
  def change_timeline(type)
    @poller.change_timeline(type) do |s, t|
      Gtk.queue { update_timeline s, t } 
    end
  end

  # Returns current timeline container or timeline specified by symbol
  # (:friends, :replies, :everyone).
  def timeline_container(tline=nil)
    unless tline
      page = @xml['timelines'].page
      name = %w(friends replies public)[page] + 'Timeline'
      @xml[name]
    else
      @xml["#{tline}Timeline"] || @xml['publicTimeline']
    end
  end

  # Updates s
  def update_timeline(status, timeline)
    container = timeline_container timeline
    shown = []
    me = begin
           @twitter.me
         rescue
         end

    unless status.nil?
      if status.is_a? Twitter::Status
        s = show_status status, container, me
        shown << s unless s.nil?
      else
        status.each do |m|
          s = show_status m, container, me
          shown << s unless s.nil?
        end
      end
      container.show_all
      @tray.tooltip  = "New tweets in the #{@poller.timeline.to_s.capitalize} timeline"
      Thread.new { Gtk.queue { shown.each { |m| @notifier.notify m } } }
    end
  end

  # Shows a single status message. Checks whether it's already on the
  # tweet container first, adds if not (also checking whether if it
  # belongs to Hechte's current user or if it is a reply).
  def show_status(status, container, me=nil)    
    unless @tweets.member? status
      @tweets << status
      w = StatusWidget.new(status, self) { |u| @state.image u }
      if me
        if status.belongs_to? @twitter.me
          w.mark :mine
        elsif status.mentions? @twitter.me
          w.mark :reply
        end
      end
      container.pack_end w, false, false
      status
    end
  end

  # Shows an error message in the current timeline.
  def show_error(error)
    Gtk.queue do
      container = timeline_container
      last = container.children.first
      if last.nil? || !last.is_a?(ErrorWidget) || last.message != error
        w = ErrorWidget.new error
        w.show
        timeline_container.pack_end w, false, false
      end
    end
  end

  # Switches timelines.
  def on_timelines_switch_page(nb, page, p_num)
    type = [:friends, :replies, :everyone][p_num]
    change_timeline type
  end

  # Posts a new tweet.
  def on_newTweet_activate(eb)
    unless eb.text.strip.empty?
      status = eb.text.strip
      eb.text = ''
      @poster = Thread.new(@twitter, @xml['friendsTimeline'], status) do |cl, cont, t|
        Gtk.queue do
          change_status :post, :starting          
          begin
            update_timeline cl.post(t), :friends
          rescue Exception => e
            show_error e.message
          end
          change_status :post, :ending
        end
      end
    end
  end

  # Notifies user of some event, while running a block that changes
  # status. &block contains either an action that updates the timeline
  # or adds a new user status.
  def change_status(where, new_status, timeline=nil)
    unless @@spinner
      spinner = Gtk::Image.new
      spinner.pixbuf_animation = Gdk::PixbufAnimation.new 'images/spinner.gif'
      spinner.set_size_request 35, -1
      spinner.show
      @@spinner = spinner
    end

    if where == :timeline
      timeline ||= @poller.timeline
      timelines = { :friends => 0, :replies => 1, :everyone => 2 }
      notebook  = @xml['timelines']
      page  = notebook.get_nth_page timelines[timeline]
      case new_status
      when :starting
        notebook.set_tab_label page, @@spinner
      when :ending
        label = Gtk::Label.new(timeline.to_s.capitalize)
        notebook.set_tab_label page, label
      end
    elsif where == :post
      post_box = @xml['postBox']
      case new_status
      when :starting
        post_box.remove @char_count
        post_box.pack_start @@spinner, false, false
      when :ending
        post_box.remove @@spinner
        post_box.pack_start @char_count, false, false
      end
    end
  end

  # Updates character count 
  def on_newTweet_changed(eb)
    count = CHAR_LIMIT - eb.text.unpack('U*').size
    if count < 20
      @char_count.markup = "<span foreground='red'>#{count}</span>"
    else
      @char_count.text = count.to_s
    end
  end

  public
  def set_tooltip(widget, text)
    @tips.set_tip widget, text, text
  end

  def update(poller_status, timeline=nil)
    change_status :timeline, poller_status, timeline
  end

  def remove(status)
    timeline_container.remove status
  end

  def block_user(user)
    timeline = timeline_container
    timeline.each { |m| timeline.remove(m) if m.message.user == user }
  end

  def reply_to(user)
    eb = @xml['newTweet']
    eb.grab_focus
    eb.text = "@#{user.screen_name} #{eb.text}"
    eb.move_cursor Gtk::MovementStep::VISUAL_POSITIONS, eb.text.size, false
  end
end

if __FILE__ == $0
  begin
    state = SavedState.restore
    HechteTwitter.new state
  rescue
    Credentials.new 
  end
  Gtk.main_with_queue 500
end
