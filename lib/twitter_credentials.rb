class TwitterCredentials
  attr_reader :username, :password
  
  def initialize(username, password=nil)
    @username  = username
    @password  = password
    @keep_pass = true
  end

  def keep_password?
    @keep_pass
  end

  def keep_password=(keep_it)
    @keep_pass = keep_it
  end
end
