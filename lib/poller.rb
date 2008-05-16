require 'monitor'
require 'observer'

module Gtk
  GTK_PENDING_BLOCKS = []
  GTK_PENDING_BLOCKS_LOCK = Monitor.new

  def Gtk.queue(&block)
    if Thread.current == Thread.main
      block.call
    else
      GTK_PENDING_BLOCKS_LOCK.synchronize do
        GTK_PENDING_BLOCKS << block
      end
    end
  end

  def Gtk.main_with_queue(timeout)
    Gtk.timeout_add timeout do
      GTK_PENDING_BLOCKS_LOCK.synchronize do
        for block in GTK_PENDING_BLOCKS
          block.call
        end
        GTK_PENDING_BLOCKS.clear
      end
      true
    end
    Gtk.main
  end
end

class TimelinePoller
  attr_accessor :frequency, :updating
  attr_reader   :timeline
  include Observable
  
  def initialize(client, type, frequency, &errors)
    @twitter = client
    @timeline = type
    @frequency = frequency
    @running = false
    @report_error = errors
    @updating = nil
    @polling  = []
  end

  def updating?
    @updating
  end

  def change_timeline(type, &block)
    stop
    @observer_peers.each { |o| o.update :ending }
    @timeline = type
    @polling.each do |t|
      t['running'] = false
      t.kill
    end
    @polling.clear
    run &block
  end

  def run(&block)
    @polling << Thread.new do
                  unless @running
                    @running = true
                    block.call fetch_statuses, @timeline
                  end
               end
    
    @polling << Thread.new(@running) do |r|
                  Thread.current['running'] = r
                  time = Time.now
                  while Thread.current['running']
                    if (Time.now - time) >= @frequency
                    @updating = true
                      time = Time.now
                      Thread.new(@timeline) { |t| block.call fetch_statuses, t }
                    end
                    sleep 0.1
                  end
                end
  end

  def fetch_statuses
    timeline = @timeline
    @observer_peers.each { |o| o.update :starting, timeline }
    begin
      tl = case @timeline
           when :everyone
             @twitter.public_timeline
           when :friends
             @twitter.friends_timeline
           when :replies
             @twitter.replies
           end
      @observer_peers.each { |o| o.update :ending, timeline }
      tl.reverse
    rescue Exception => e
      @observer_peers.each { |o| o.update :ending, timeline }
      @report_error.call e.message
      nil
    end
  end

  def stop
    @running = false
  end
end
