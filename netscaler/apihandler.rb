
# handle all the REST calls to the netscaler load balancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require 'net/http'
require 'io/console'
require_relative '../../rl_credentials/lib/credentials.rb'

include RLCredentials


class NSLBApiHandler

    attr_reader :dc

    # get everything setup
    # 
    # we need to know which netscaler load balancer we're using
    def initialize(*args)
      print "initializing NSLBApiHandler\n"
      @dc = args[0]
      @lb_url = "http://lb.#{dc}.reachlocal.com"     
      load_credentials
    end


    # if we don't have credentials supplied by the cli or rundeck, prompt the user
    def load_credentials
	  @username, @password = RLCredentials.loadbalancer("lb")
      print "username: ", @username, "\n"
      print "password: "
      @password = STDIN.noecho(&:gets).chomp
      print "\n"
    end


    # if we can use one connection for all our transactions, let's do that.  
    # however, uncertain if the HTTP library can handle it.  may have to initiate
    # a new connection per request
    def http_connect
      #{'Content-Type' => 'application/vnd.com.citrix.netscaler.login+json'})
      print "stub"
    end


    # login to the LB
    def callrest_login
        print "login to LB\n" 
        @uri = URI("http://lb.#{@dc}.reachlocal.com/nitro/v1/config/lbvserver/")
        @request = Net::HTTP::Get.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"

    end 


    # GET commands to the LB
    def callrest_getstats
        print "get stats\n"
        @uri = URI("http://lb.#{@dc}.reachlocal.com/nitro/v1/config/lbvserver/")
        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)

            if response.code == "200"
                result = JSON.parse(response.body)
                puts result
            end
        }

    end

    # create LB objects
    def callrest_create
        print "creating a LB object"
    end

    # delete LB objects
    def callrest_delete
        print "deleting a LB object"
    end


end
