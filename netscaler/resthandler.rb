
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

    # get everything setup
    # 
    # we need to know which netscaler load balancer we're using
    def initialize(*args)
      print "initializing NSLBRestHandler\n"
      @dc = args[0]
      @lb_host = "lb.#{dc}.reachlocal.com"     
      load_credentials
      build_uri
    end

    # build the a basic uri object.  update the path locally for
    # any functions requiring a change
    def build_uri
        print "building uri..."
        @uri = URI::HTTP.build({
            :host       => "#{@lb_host}",
            :path       => "",
            :port       => "",
            :scheme     => "http",
            :fragment   => ""
        })
        print "done!\n"
        print "uri: ",  @uri
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
      print "stub"
    end


    # login to the LB
    def call_rest_login
        print "login to LB\n" 
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Get.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
    end 


    # get a list of lb vservers
    def call_rest_getlbvstats
        print "get lb vserver stats\n"
        @uri.path = "/nitro/v1/config/lbvserver/"
        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)

            if response.code == "200"
                result = JSON.parse(response.body)
                File.open("lb.#{dc}-lbvserver-stats.json", "w") do |f|
                    f.write(JSON.pretty_generate(result))
                end
            end
        }

    end

    # create LB objects
    def call_rest_create

        print "setting up a POST\n"
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"

        type = "lb vserver\n"
        print "creating a #{type} LB object\n"
        @uri.path = "/nitro/v1/config/lbvserver/"
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
                if response.code == "200"
                    print "success!\n"
                    print "code: ", response.code.to_i, "\n"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end

            # save the config
            @uri.path = "/nitro/v1/config/nsconfig"
            @uri.query = "action=save"
            @request.body = '{
                "nsconfig":
                {
                }
            }'
            saved = http.request(@request)

                if saved.code == "200"
                    print "success!\n"
                    print "code: ", response.code.to_i, "\n"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                end
        }
                
    end

    def call_rest_saveconfig
        print "saving config\n"
        @uri.path = "/nitro/v1/config/nsconfig"
        @uri.query = "action=save"
        @request.add_field('Content-Type', 'application/vnd.com/citrix.netscaler.lbvserver+json')
        @request.body = '{
            "nsconfig":{}
        }'

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "200"
                    print "saved!\n"
                else
                    print "save failed!\n"
                end
        }

    end

    # delete LB objects
    def call_rest_delete
        print "deleting a LB object"
    end

    # save LB objects
    def call_rest_save
        print "saving changes"
    end

end
