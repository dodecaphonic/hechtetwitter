begin
  require 'net/http'
  require 'uri'
  require 'open-uri'
  require 'json'
  require 'htmlentities'
  require 'uri'
rescue
  require 'rubygems'
  retry
end

module Twitter
  class ExcessRequestsException < StandardError; end
  class MalformedDataException  < StandardError; end

  class Client
    BASEURL = 'twitter.com'.freeze
    FORMAT  = '.json'
    
    def initialize(user, password)
      @user  = user
      @password = password
      @users = {}
      @me    = nil
    end

    def show(who)
      request = "/users/show/#{who}#{FORMAT}"
      make_user fetch(request)
    end

    def me
      @me ||= show @user
    end

    def public_timeline(since_id=nil)
      request = "/statuses/public_timeline#{FORMAT}"
      request << "?since_id=#{since_id}" if since_id
      build_message_list fetch(request, :get, :auth => false)
    end

    def friends_timeline(opts={})
      request = "/statuses/friends_timeline#{FORMAT}"
      build_message_list fetch(request, :get, opts)
    end

    def replies
      request = "/statuses/replies#{FORMAT}"
      build_message_list fetch(request)
    end

    def post(text)
      text = text[0...160]
      request = "/statuses/update#{FORMAT}"
      output = fetch request, :post, :fields => { :status => text }
      make_message output
    end

    def friends(user, opts=nil)
      request = "/statuses/friends/#{user}#{FORMAT}"
      opts.each { |o, v| opts[o] = URI.encode v } if opts
      data = fetch(request, :get, opts)
      data.map { |u| make_user u }
    end

    def block_user(user)
      request = "/blocks/create/#{user.id}#{FORMAT}"
      fetch request
      nil
    end

    def user_timeline
      request = "/statuses/user_timeline#{FORMAT}"
      build_message_list fetch(request)
    end

    def remove_status(status)
      request = "/statuses/destroy/#{status.id}#{FORMAT}"
      fetch request
    end

    def show_status(status_id)
      request = "/statuses/show/#{status_id}#{FORMAT}"
      build_message_list fetch(request)
    end

    def favorites
      request = "/favorites#{FORMAT}"
      build_message_list fetch(request)
    end

    def make_favorite(message)
      request = "/favorites/create/#{message.id}#{FORMAT}"
      make_message fetch(request)
    end

    def remove_favorite(message)
      request = "/favorites/destroy/#{message.id}#{FORMAT}"
      make_message fetch(request)
    end

    private
    def fetch(what, method=:get, opts={})
      auth = opts[:auth] || true
      data = Net::HTTP.start(BASEURL) do |http|
               req = if method == :get
                       if opts[:fields]
                         params = '?'
                         opts[:fields].map { |f, v| "#{f}=#{URI.encode v.to_s}" }
                         params << opts.join('&')
                         what << params
                       end
                       Net::HTTP::Get.new what
                     else
                       r = Net::HTTP::Post.new what
                       if opts[:fields]
                         fields = {}
                         opts[:fields].each { |o, v| fields[o.to_s] = v }
                         r.set_form_data fields if opts
                       end
                       r
                     end
               req.basic_auth @user, @password if auth
               http.request(req).body
             end
      check_data data
    end

    def check_data(data)
      begin
        data = JSON.parse data
        raise ExcessRequestsException, data['error'] if data.is_a?(Hash) && data['error']
        data
      rescue JSON::ParserError => jse
        raise MalformedDataException, "Malformed output from Twitter's servers."
      rescue ExcessRequestsException => ere
        raise ere
      end
    end
    
    def build_message_list(input)
      input.map { |m| make_message m }
    end

    def make_user(data)
      @users[data['id']] ||= User.new(data['id'], data['name'], 
                                      data['screen_name'], data['location'], 
                                      data['description'], 
                                      data['profile_image_url'], 
                                      data['url'], data['is_protected'], self)
    end
    
    def make_message(m)
      user = make_user m['user']
      text = HTMLEntities.decode_entities(m['text']).gsub('&', '&amp;').
                                                     gsub('<', '&lt;').
                                                     gsub('>', '&gt;')
      Status.new(m['id'], Time.parse(m['created_at']), text, user,
                 m['favorited'], m['source'], self)
    end
  end

  class User
    attr_reader :id, :name, :screen_name, :location,
                :description, :profile_image_url, :url

    def initialize(id, name, screen_name, location, description,
                   profile_image_url, url, is_protected, client)
      @id = id
      @name = name
      @screen_name = screen_name
      @location = location
      @description = description
      @profile_image_url = profile_image_url
      @url = url
      @is_protected = is_protected
      @image = nil
      @friends = nil
      @followers = nil
      @client = client
    end

    def is_protected?
      @is_protected
    end

    def image
      begin
        @image ||= open(URI.encode(@profile_image_url)).read
      rescue
        @image = nil
      end
    end

    def friends
      @friends ||= @client.friends @screen_name
    end

    def to_s
      "#@id\n#@name\n#@screen_name\n#@location\n#@description\n"
    end

    def block!
      @client.block_user(self) if self != @client.me
    end
  end

  class Status
    attr_reader :id, :created_at, :text, :user
    def initialize(id, created_at, text, user, favorited,
                   source, client)
      @id = id
      @created_at = created_at
      @text = text
      @user = user
      @favorited = favorited
      @source = source
      @client = client
    end

    def ==(other)
      @id == other.id
    end

    def mentions?(user)
      !(@text =~ /#{user.screen_name}/i).nil?
    end

    def belongs_to?(user)
      @user == user
    end

    def favorite!
      @client.make_favorite self
      @favorited = true
    end

    def unfavorite
      @client.remove_favorite self
      @favorited = false
    end

    def favorite?
      @favorited
    end
    
    def destroy!
      @client.remove_status self
    end

    def to_s
      "#{@user.to_s}\n\n#{@created_at.to_s}\n#{@text}\n#{@user}"
    end
  end
end
