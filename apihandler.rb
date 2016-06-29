
# handle all the REST calls to the loadbalancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require_relative '../rl_credentials/credentials.rb'
include RLCredentials

class LBApiHandler

    attr_reader :dc

    # get everything setup
    def initialize(*args)
      @dc = args[0]
      lb_url = "http://lb.#{dc}.reachlocal.com"     
      print "lb_url: #{lb_url}\n"

	  load_credentials
    end

    def load_credentials
      print "loading credentials from ../rl_credentials/credentials.rb\n"
	  rlcreds = RLCredentials.loadbalancer("lb")
    end

    # make the call 
    def callrest
		print "in callrest\n"
    end 

end
