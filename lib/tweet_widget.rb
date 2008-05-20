class TwitterWidget < Gtk::DrawingArea
  attr_reader :message, :image_fetcher
  def initialize(message, parent=nil, marked=false, &image_fetcher)
    super()
    @message = message
    @width   = allocation.width
    @height  = 80
    @parent  = parent
    @mark    = marked
    @image_fetcher = image_fetcher
    set_size_request @width, @height
    define_behavior
  end

  def define_behavior
    signal_connect('expose-event') { expose }
    set_events(Gdk::Event::ENTER_NOTIFY_MASK |
               Gdk::Event::LEAVE_NOTIFY_MASK |
               Gdk::Event::BUTTON_PRESS_MASK)
    signal_connect('enter_notify_event') { mouse_over }
    signal_connect('leave_notify_event') { mouse_out  }
    signal_connect('button_press_event', &method(:clicked))
  end

  def mouse_over
    cr = window.create_cairo_context
    cr.set_source_rgba 1, 1, 1, 0.1
    cr.rectangle 0, 0, @width, @height - 2
    cr.fill
  end

  def mouse_out
    window.invalidate(Gdk::Rectangle.new(0, 0, @width, @height), true)
  end

  def clicked(w, e)
    nil
  end

  def marked?
    !@mark.nil?
  end

  def mark(mark)
    @mark = mark
  end

  def unmark
    @mark = nil
  end

  def expose(r=0, g=0, b=0)
    @width = allocation.width
    cr = window.create_cairo_context
    # background color
    gr = Cairo::LinearPattern.new 0, @height / 2, @width, @height / 2
    gr.add_color_stop_rgb 0, r, g, b
    gr.add_color_stop_rgba 0.5, r + 0.18, g + 0.18, b + 0.18, 0.5
    gr.add_color_stop_rgb 1, r, g, b
    cr.rectangle 0, 0, @width, @height
    cr.set_source_rgb r, g, b
    cr.fill
    cr.rectangle 0, 0, @width, @height
    cr.set_source gr
    cr.fill

    if marked?
      case @mark
      when :reply
        cr.set_source_rgba 1, 0, 0, 0.2
      when :mine
        cr.set_source_rgba 0.4, 0.8, 0.2, 0.3
      end
      cr.rectangle 0, 0, @width, @height
      cr.fill
      cr.set_source_rgb r, g, b
    end

    cr.line_width = 1.0
    cr.move_to 0, @height - 2
    cr.set_source_rgba 0, 0, 0, 1
    cr.line_to @width, @height - 2
    cr.stroke

    cr.move_to 0, @height - 1
    cr.set_source_rgba 1, 1, 1, 0.2
    cr.line_to @width, @height - 1
    cr.stroke
    
    tweet_image
    cr
  end

  def draw_markup(markup)
    cr = window.create_cairo_context
    cr.move_to 65, 10
    cr.set_source_rgb 1, 1, 1
    pl = cr.create_pango_layout
    pl.wrap = Pango::WRAP_WORD
    pl.width = (@width - 100) * Pango::SCALE
    pl.markup = markup
    cr.show_pango_layout pl
  end

  def place_pixbuf(pixbuf)
    window.draw_pixbuf nil, pixbuf, 0, 0, 5, 10, pixbuf.width, pixbuf.height, Gdk::RGB::DITHER_NORMAL, 0, 0
  end

  protected
  def tweet_image
    nil
  end
end

class StatusWidget < TwitterWidget
  IMAGES = { :star => { #:over => Gdk::Pixbuf.new('images/star_over.png'),
                        :clicked => Gdk::Pixbuf.new('images/star_clicked.png'), 
                        :normal => Gdk::Pixbuf.new('images/star_normal.png') },
             :reply => { :normal => Gdk::Pixbuf.new('images/reply.png') }
           }
  
  def initialize(message, parent=nil, marked=false)
    super
    @@pixbufs ||= {}
    @links = nil
    @pango      = nil
    @star_pos   = nil
    @reply_pos  = nil
  end

  def clicked(w, e)
    if e.button == 3
      menu = Gtk::Menu.new
      blk  = Gtk::MenuItem.new "Block user"
      blk.signal_connect('activate') do
        @message.user.block!
        @parent.block_user @message.user
      end
      fav  = Gtk::CheckMenuItem.new "Set tweet as favorite"
      fav.active = @message.favorite?
      fav.signal_connect('activate') do
        !@message.favorite? ? @message.favorite! : message.unfavorite
      end
      gt   = Gtk::MenuItem.new "Go to user's twitter page"
      gt.signal_connect('activate') { open_link "http://twitter.com/#{@message.user.screen_name}" }
      menu.append blk
      menu.append fav
      menu.append gt
      
      if @mark == :mine
        rem = Gtk::MenuItem.new "Remove tweet"
        rem.signal_connect('activate') do
          @message.destroy!
          @parent.remove self
        end
        menu.append rem
      end

      unless @links.nil? or @links.empty?
        lnklbl = Gtk::MenuItem.new 'Links in this tweet'
        links  = Gtk::Menu.new
        @links.each do |l|
          link = Gtk::MenuItem.new l
          link.signal_connect('activate') { open_link l }
          links.append link
        end
        links.show_all
        lnklbl.submenu = links
        menu.append lnklbl
      end
      
      menu.show_all
      menu.popup nil, nil, e.button, e.time
    elsif e.button == 1
      if in_star?(e.x, e.y)
        @message.favorite? ? @message.unfavorite : @message.favorite!
        mouse_out
      elsif in_reply?(e.x, e.y)
        @parent.reply_to @message.user
      end
    end
  end

  def in_star?(x, y)
    in_shape? x, y, @star_pos
  end

  def in_reply?(x, y)
    in_shape? x, y, @reply_pos
  end

  def in_shape?(x, y, shape)
    x >= shape[0] && y >= shape[1] && x <= shape[2] && y <= shape[3]
  end
  
  def mouse_over
    super
    hl = how_long_ago?(@message.created_at)
    @parent.set_tooltip(self, hl) unless @parent.nil?
  end

  def expose    
    super
    width, height = allocation.width, allocation.height
    draw_star  [width - 30, 10, width - 14, 26]
    draw_reply [width - 30, 35, width - 14, 51]
    url    = /(http:\/\/\S+)/
    @links  ||= @message.text.scan(url).flatten 
    markup  = @message.text.gsub url, '<span foreground="#ccffff" font_desc="Sans Bold 8">\1</span>'
    @pango = draw_markup "<span font_desc='Sans Bold 9'>#{@message.user.name}</span>\n<span font_desc='Sans 8'>#{markup}</span>"
  end

  def draw_star(pos)
    @star_pos = pos
    pb = @message.favorite? ? IMAGES[:star][:clicked] : IMAGES[:star][:normal]
    window.draw_pixbuf nil, pb, 0, 0, pos[0], pos[1], pb.width, pb.height, Gdk::RGB::DITHER_NORMAL, 0, 0
  end

  def draw_reply(pos)
    @reply_pos = pos
    pb = IMAGES[:reply][:normal]
    window.draw_pixbuf nil, pb, 0, 0, pos[0], pos[1], pb.width, pb.height, Gdk::RGB::DITHER_NORMAL, 0, 0
  end

  protected
  def open_link(url)
    system 'firefox', '-new-window', url
  end
  
  def tweet_image
    unless @@pixbufs[@message.user]
      Thread.new(@message) do |msg|
        i = image_fetcher ? image_fetcher.call(msg.user) : msg.user.image
        unless i.nil?
          Gtk.queue do
            l = Gdk::PixbufLoader.new
            l.last_write msg.user.image
            pb = l.pixbuf
            place_pixbuf pb
            @@pixbufs[msg.user] = pb
          end
        end
      end
    else
      Gtk.queue { place_pixbuf @@pixbufs[@message.user] }
    end
  end
  
  def how_long_ago?(time)
    t = (Time.now - time).to_i
    case t
    when 0..59
      "just now"
    when 60..3590
      m = t / 60
      "#{m} minute#{m > 1 ? 's' : ''} ago"
    when 3600..86359
      h = t / 3600
      "#{h} hour#{h > 1 ? 's' : ''} ago"
    else
      d = t / 86400
      "#{d} days ago"
    end
  end
end

class ErrorWidget < TwitterWidget
  ERRORIMAGE = Gdk::Pixbuf.new 'images/error.png'
  def initialize(message, parent=nil, marked=false)
    super
  end

  def expose
    super 0.54, 0.45, 0.08
    draw_markup "<span font_desc='Sans 8'>#{@message}</span>"
  end

  protected
  def tweet_image
    place_pixbuf ERRORIMAGE
  end
end
