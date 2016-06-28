
# handle all the REST calls to the loadbalancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend
#

require 'json'

class LBApiHandler

    attr_reader :dc

    # get everything setup
    def initialize(*args)
      @dc = args[0]
      lb_url = "http://lb.#{dc}.reachlocal.com"     
      print "lb_url: #{lb_url}\n"
    end

    # make the call 
    def callrest
      print "loading credentials\n"
      creds_file = File.open('apicreds.json', "rb")
      content = creds_file.read
      creds_hash = JSON.parse(content)
      print "username: ", creds_hash['login']['username'], "\n"
      print "password: ", creds_hash['login']['password'], "\n"
    end 

end
