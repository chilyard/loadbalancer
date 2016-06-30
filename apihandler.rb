
# handle all the REST calls to the loadbalancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require 'net/http'
require 'io/console'
require_relative '../rl_credentials/credentials.rb'

include RLCredentials




class LBApiHandler

    attr_reader :dc

    # get everything setup
    def initialize(*args)
      print "initializing LBApiHandler\n"
      @dc = args[0]
      @lb_url = "http://lb.#{dc}.reachlocal.com"     
      load_credentials
    end

    def load_credentials
	  @username, @password = RLCredentials.loadbalancer("lb")
      print "username: ", @username, "\n"
      print "password: "
      @password = STDIN.noecho(&:gets).chomp
    end

    # setup the connection
    def http_connect
      print "nothin"
    end

    # setup the login
    def callrest_login
        @path = "/nitro/v1/config/login/"
        uri = URI("#{@lb_url}#{@path}")
        @host = uri.host
        @port = 80

        @payload = { 'login' => { 'username' => "#{@username}", 'password' => "#{@password}" }}.to_json

        request = Net::HTTP::Post.new(@path, initheader = {'Content-Type' => 'application/vnd.com.citrix.netscaler.login+json'})
            request.basic_auth @username, @password
            request.body = @payload
            response = Net::HTTP.new(@host, @port).start { |http|
                http.request(request)
            }
         print "Response #{response.code} #{response.message}: \n"
         print "#{response.body}"
    end 

    # GET commands to the LB
    def callrest_getstats
      @path = "/nitro/v1/config/lbvserver/"
      uri = URI("#{@lb_url}#{@path}") 
      request = Net::HTTP.get()
        #http.request_get('http://lb.wh.reachlocal.com/nitro/v1/config/lbvserver') { |response|
        #print response.read_body 
      #}
    end


end
