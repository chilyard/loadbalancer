
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

    # required args: 
    # dc - caller must pass the datacenter {wh, lax, iad, nrt, syd, ams}
    # env - caller must pass sdlc environment {dev, qa, stg, prod}
    # country - caller must pass country {usa, can, aus, jpn, gbr, eur}
    # service - caller must pass the service "nice name," i.e. "yjpconnector" 
    #
    # optional args:
    # username - this may come from the calling source, like rundeck.  or we could prompt the user
    # password - this may come from the calling source, like rundeck.  or we could prompt the user
    def initialize(*args)
      print "initializing NSLBRestHandler\n"
      @dc = args[0]
      @env = args[1]
      @country = args[2]
      @service = args[3]
      username = args[4]
      password = args[5]
      @projectname = args[6]

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


    # if we don't have credentials supplied by the cli or rundeck, attempt to load from a common
    # library (RLCredentials).  failing that, prompt the user
    def load_credentials(username, password)

        if username.empty? || password.empty?
            # unused feature, for now  
	        #@username, @password = RLCredentials.load("lb")
            print "username: "
            @username = STDIN.gets.chomp
            print "password: "
            @password = STDIN.noecho(&:gets).chomp
            print "\n"
        else
            @username = username
            @password = password
        end

        # we'll want to test the credentials here by calling the rest_login
        call_rest_login

    end


    # login to the LB
    def call_rest_login
        print "checking credentials..." 
        @uri.path = "/nitro/v1/config/login/"
        @request = Net::HTTP::Post.new(@uri)
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.login+json')
        @request.body = { :login => { :username => "#{@username}", :password => "#{@password}" }}.to_json 

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                else
                    print "fail!\n"
                    print JSON.parse(response.body), "\n"
                end
        }
    end 


    # get a list of lb vservers
    def call_rest_getlbvstats
        print "get lb vserver stats\n"
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Get.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver+json')

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

    # create LB objects (this is busy and should be broken up)
    #
    # arguments: 
    #  # arguments
    # ssl or nonssl - if ssl is required further setup will be required.
    #   add ssl cs vserver
    #   bind cs vserver certkeyName
    #   bind ssl cipherName
    # content switching server required? - this one is more complicated as it's shared.
    # site specific? {wh, lax, iad, ams, syd, nrt}
    # platform specific? {usa, can, eur, gbr, aus, jpn}
    # environment {dev, qa, stg, prod}
    #
    # order of operations and requirements
    #
    # add server FQDN FQDN
    # add lbvserver NAME (IP address if standalone)
    # add serviceGroup NAME
    # add lb monitor NAME ("GET /project/health/up")
    # add cs policy NAME (STARTSWITH "/project/")
    # bind serviceGroup NAME SERVER PORT
    # bind servcieGroup NAME -monitorName NAME
    # bind cs vserver NAME -policName NAME -targetLBVserver NAME numb++
    #
    # error handling
    # if one of the components fails to create properly then delete the ones we created (stack a hash of success)
    # there's no need to leave the LB in a weird state
    # OR perhaps if we just don't save the running config and exit, we're good
    def call_rest_create(*args)

        print "creating a lbvserver..."
        call_create_lbvserver

        # save the configs if there were no errors
        # enable this when we're ready to actually save the config
        #call_rest_saveconfig
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


    private
    def call_create_server
        print "do nuttin"
    end

    def call_create_lbvserver(ipaddress="0.0.0.0", args = {})
        # hard coded for testing
        @projectname = "vs-rundeckdemo-usa-qa-wh"
        # hard coded for testing
        ipaddress = "10.126.255.53"
        # hard coded for testing
        port = "80"
        # hard coded for testing
        servicetype = "HTTP"
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver+json')
        # add lb vserver qvs-wh-nx1-jpn-yjpconnector HTTP 0.0.0.0 0 -persistenceType COOKIEINSERT -timeout 15 -lbMethod LRTM -cltTimeout 3600 -appflowLog DISABLED
        @request.body = { :lbvserver => { :name => "#{@projectname}", :servicetype => "#{servicetype}", :ipv46 => "#{ipaddress}", :port => "#{port}", :persistencetype => "COOKIEINSERT", :timeout => "15", :lbmethod => "LRTM", :cltTimeout => "1800", :appflowlog => "DISABLED" } }.to_json 

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }
    end

    def call_create_csvserver
        print "do nuttin"
    end

    def call_create_servicegroup
        print "do nuttin"
    end

    def call_create_monitor
        print "do nuttin"
    end

    def call_create_cspolicy
        print "do nuttin"
    end

end
