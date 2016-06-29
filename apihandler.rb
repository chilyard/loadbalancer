
# handle all the REST calls to the loadbalancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require '../rl_credentials/credentials.rb'

class LBApiHandler

    attr_reader :dc

    # get everything setup
    def initialize(*args)
      @dc = args[0]
      lb_url = "http://lb.#{dc}.reachlocal.com"     
      print "lb_url: #{lb_url}\n"
    end

    def load_credentials
    end

    # make the call 
    def callrest
      print "loading credentials from ../rl_credentials/credentials.rb\n"
    end 

end
