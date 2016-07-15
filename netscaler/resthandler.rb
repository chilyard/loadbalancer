
# handle all the REST calls to the netscaler load balancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require 'net/http'
require 'io/console'
require_relative '../../rl_credentials/lib/credentials.rb'

include RLCredentials


class NSLBRestHandler

    attr_reader :dc 

    # initialization
    #
    # what we'll do, here:
    # check arguments passed
    # verify credentials against the netscaler endpoint
    #
    # required args: 
    # dc - caller must pass the datacenter {wh, lax, iad, nrt, syd, ams}
    # env - caller must pass sdlc environment {dev, qa, stg, prod}
    # country - caller must pass country {usa, can, aus, jpn, gbr, eur}
    # service - caller must pass the service "nice name," i.e. "yjpconnector" 
    #
    # optional args:
    # username - this may come from the calling source, like rundeck.  or we could prompt the user
    # password - this may come from the calling source, like rundeck.  or we could prompt the user
    #
    def initialize(*args)
      print "initializing NSLBRestHandler\n"
      @dc = args[0]
      @env = args[1]
      @country = args[2]
      @service = args[3]
      username = args[4]
      password = args[5]

      @lb_host = "lb.#{dc}.reachlocal.com"     
      build_uri
      load_credentials(username, password)
    end

    # build a basic uri object.  update the path local to the function for
    # any functions that require it
    def build_uri
        print "building uri object..."
        @uri = URI::HTTP.build({
            :host       => "#{@lb_host}",
            :path       => "",
            :port       => "",
            :scheme     => "http",
            :fragment   => ""
        })
        print "done!\n"
    end


    # if we don't have credentials supplied by the cli or rundeck, prompt the user
    def load_credentials(username, password)
        if username.empty? || password.empty?
            # unused feature, for now  
	        @username, @password = RLCredentials.loadbalancer("lb")
            print "username: ", @username, "\n"
            print "password: "
            @password = STDIN.noecho(&:gets).chomp
            print "\n"

        else
            print "username and password already set\n"
            print "u: ", username, "\n"
            print "p: ", password, "\n"
        end
        # we'll want to test the credentials here by calling the rest_login
        # function
    end


    # login to the LB
    def call_rest_login
        print "checking credentials..." 
        @uri.path = "/nitro/v1/config/login/"
        @request = Net::HTTP::Post.new(@uri)
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.login+json')
        @request.body = '{
            "login": 
                {
                "username":"chuck.hilyard",
                "password":"blahblah"
                }
            }'

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "credential check success!\n"
                else
                    print "credential check fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }
    end 


    # get a list of lb vservers
    def call_rest_getlbvstats
        print "get lb vserver stats\n"
        @uri.path = "/nitro/v1/config/lbvserver/"
        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)

            if response.code == "200"
                result = JSON.parse(response.body)
                File.open("lb.#{dc}-lbvserver-stats.json", "w") do |file|
                    file.write(JSON.pretty_generate(result))
                end
            end
        }

    end

    # create LB objects
    #
    # arguments: 
    def call_rest_create(type="null")
        print "creating a #{type}..."
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver+json')
        @request.body = '{
                "lbvserver":
                    {
                    "name":"testlbvserver",
                    "servicetype":"http",
                    "ipv46":"0.0.0.0",
                    "persistencetype":"NONE",
                    "lbmethod":"LRTM",
                    "clttimeout":"1800",
                    "appflowlog":"DISABLED"
                    }
        }'


        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                    call_rest_saveconfig
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }
                
    end
 

    # save the config
    def call_rest_saveconfig
        print "saving config..."
            @uri.path = "/nitro/v1/config/nsconfig"
            @uri.query = "action=save"
            @request = Net::HTTP::Post.new(@uri)
            @request.basic_auth "#{@username}", "#{@password}"
            @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.nsconfig+json')
            @request.body = '{
                "nsconfig":{}
                }'

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "200"
                    print "success!\n"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }
    end


    # delete LB objects
    def call_rest_delete
        print "deleting a LB object"
            @uri.path = "/nitro/v1/config/lbvserver/testlbvserver"
            @request = Net::HTTP::Delete.new(@uri)
            @request.basic_auth "#{@username}", "#{@password}"
            @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver+json')
            @request.body = '{
                "lbvserver":
                    {
                    "name":"testlbvserver",
                    "lbmethod":"LRTM"
                    }
            }'

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "200"
                    print "success!\n"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }
                    
    end

end
