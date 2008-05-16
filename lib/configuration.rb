require 'madeleine'
require 'open-uri'

class CachedImage
  attr_reader :user_id, :url
  def initialize(user_id, url)
    @user_id = user_id
    @url     = url
    @image   = File.join SavedState::IMAGE_PATH, "#{user_id}.jpg"
    cache!
  end

  def cached?
    File.exist? @image
  end
  
  def cache!
    open(@image, 'wb') { |f| f << open(URI.encode(@url)).read }
  end
  
  def image
    cache! unless cached?
    open(@image, 'rb').read
  end
end

class SavedState
  HECHTE_PATH = File.join ENV['HOME'], '.hechtetwitter'
  CONFIG_PATH = File.join HECHTE_PATH, 'current_state'
  IMAGE_PATH  = File.join HECHTE_PATH, 'cached_images'
  attr_reader :credentials
  
  def initialize(credentials)
    @credentials = credentials
    @cache       = {}
    create_directories unless directories_ok?
  end

  def add_image_to_cache(user)
     @cache[user.id] = CachedImage.new user.id, user.profile_image_url
  end

  def image_cached?(user)
    cached = @cache[user.id]
    cached ? cached.url == user.profile_image_url : false
  end

  def image(user)
    add_image_to_cache user unless image_cached? user
    @cache[user.id].image
  end
  
  def self.restore
    if File.exist? CONFIG_PATH
      SnapshotMadeleine.new(CONFIG_PATH)
    else
      raise StandardError, "No state saved yet"
    end
  end

  def self.create(credentials)
    SnapshotMadeleine.new(CONFIG_PATH) { SavedState.new credentials }
  end

  private
  def directories_ok?
    if !(File.exist? HECHTE_PATH) || !(File.exist? IMAGE_PATH)
      false
    else
      true
    end
  end

  def create_directories
    Dir.mkdir HECHTE_PATH unless File.exist? HECHTE_PATH
    Dir.mkdir IMAGE_PATH  unless File.exist? IMAGE_PATH
  end
end
