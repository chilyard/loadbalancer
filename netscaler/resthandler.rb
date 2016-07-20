
# handle all the REST calls to the netscaler load balancer, here.
#
# we'll want a cli in front of this in addition to using rundeck or some other rbac gui frontend

require 'json'
require 'net/http'
require 'io/console'
require_relative '../../rl_credentials/lib/credentials.rb'

include RLCredentials


class NSLBRestHandler

    attr_reader :datacenter

    # required args: (these configs should be puppetized) 
    # datacenter - caller must pass the datacenter {wh, lax, iad, nrt, syd, ams}
    # environment - caller must pass sdlc environment {dev, qa, stg, prod}
    # platform - caller must pass platform {usa, can, aus, jpn, gbr, eur}
    # servicename - caller must pass the service "nice name," i.e. "yjpconnector" 
    #
    # optional args:
    # username - this may come from the calling source, like rundeck.  or we could prompt the user
    # password - this may come from the calling source, like rundeck.  or we could prompt the user
    def initialize(*args)
      print "initializing NSLBRestHandler\n"
      @datacenter = args[0]     # this is the datacenter location, may be lax, iad, syd, nrt, ams
      @environment = args[1]    # this is the environment, may be dev, qa, stg, prod
      @platform = args[2]       # this is the platform, may be; aus, can, jpn, eur, gbr, usa
      @servicename = args[3]    # this is the service nice name, like "yjpconnector"
      @nettype = args[4]        # this is where node will live in openstack (Web or App)
      @action = args[5]         # either "create" or "delete" - user must supply
      username = args[6]
      password = args[7]

      # create a status hash.  we'll track what we've built in the hash.
      # if we fail on anything we'll source the hash for undoing what we've done.
      # additionaly, as an example, we can use the hash to bind the nodes we created to the servicegroup
      # that was created
      @status_hash = {}
      # server_array contains the FQDN nodes we added to the loadbalancer.  it's used here in case we need to 
      # delete them due to failure or if we need this info for use in construction of other LB objects
      @server_array = []

      # construct a basic uri object, gets updated during different calls (in respective functions) to the NS REST interface
      build_uri

      # we'll check the framework to see if credentials were supplied.  we'll also check
      # for credentials supplied from the cli.  if all else fails, request credentials from the user
      load_credentials(username, password)

      case @action
            when "create"
                call_create_server
                call_create_servicegroup
                call_create_lbvserver
                call_bind_objects
            when "delete"
                print "deleting stuff"
            else
                print "din do nuffin"
            end

    end

    # build a basic uri object.  update the path local to the function for
    # any functions that require it
    def build_uri
        print "building uri object..."
        @uri = URI::HTTP.build({
            :host       => "lb.#{@datacenter}.reachlocal.com",
            :path       => "",
            :port       => "",
            :scheme     => "http",
            :fragment   => ""
        })
        print "done!\n"
    end


    # if we don't have credentials supplied by the cli or rundeck, attempt to load from a common
    # library (RLCredentials).  failing that, prompt the user.  this will eventually be built into
    # the framework, elsewhere
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
        print "validating credentials..." 
        @uri.path = "/nitro/v1/config/login/"
        @request = Net::HTTP::Post.new(@uri)
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.login+json')
        @request.body = { :login => { :username => "#{@username}", :password => "#{@password}" } }.to_json 

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                else
                    print "fail!\n"
                    print JSON.parse(response.body), "\n"
                    abort()
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
                File.open("lbvserver-stats.json", "w") do |file|
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
    # bind serviceGroup NAME -monitorName NAME
    # bind cs vserver NAME -policName NAME -targetLBVserver NAME numb++
    #
    # error handling
    # if one of the components fails to create properly then delete the ones we created (stack a hash of success)
    # there's no need to leave the LB in a weird state
    # OR perhaps if we just don't save the running config and exit, we're good
    def call_rest_create(*args)

        print "creating LB objects..."
        #call_create_lbvserver
        call_create_servicegroup

        # save the configs if there were no errors
        # enable this when we're ready to actually save the config
        call_rest_saveconfig
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
        print "deleting a LB object..."
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


    # here we add the node entries to the LB
    #
    # a server name is comprised of the following variables
    # $servicename-$platform-$nettype{$quantity}.$environment.$datacenter.reachlocal.com
    #
    # get the quantity of nodes from the user and increment, beginning at 01.  the NS rest interface
    # will spit back a "record exists" message.  if that happens we must cease operation as we could inadvertently
    # bind to an existing service, which may not be desired
    #
    # we'll default to a quantity of 2 nodes
    def call_create_server(quantity = 2)
       abort("you either passed a zero quantity of servers or way too many, default is 2") if quantity == 0 || quantity >= 6
  
       1.upto(quantity) { |x|  
            print "adding server..."
            serverfqdn = "#{@servicename}-#{@platform}-#{@nettype}0#{x}.#{@environment}.#{@datacenter}.reachlocal.com"
            @uri.path = "/nitro/v1/config/server/"
            @uri.query = "action=add"
            @request = Net::HTTP::Post.new(@uri)
            @request.basic_auth "#{@username}", "#{@password}"
            @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.server+json')
            @request.body = { :server => { :name => "#{serverfqdn}", :domain => "#{serverfqdn}" } }.to_json 

            Net::HTTP.start(@uri.host, @uri.port) { |http|
                response = http.request(@request)
                    if response.code == "201"
                        print "success!\n"
                        # add this server to the array
                        @server_array.push(serverfqdn)
                    else
                        print "fail!\n"
                        print "code: ", response.code.to_i, "\n"
                        print "body: ", response.body, "\n"
                    end
            }
        }
    end

    def call_create_servicegroup
        # example: add serviceGroup qsg-wh-nx1-usa-geminishim-http HTTP -maxClient 0 -maxReq 0 -cip ENABLED RL-SRC-IP -usip NO -useproxyport YES -cltTimeout 3600 
        # -svrTimeout 3600 -CKA NO -TCPB YES -CMP NO -appflowLog DISABLED
        print "creating servicegroup..."
        @sgservice_name = "sg-#{@servicename}-usa-qa-wh"
        sg_type = "HTTP"
        sg_state = "ENABLED"
        clttimeout = "3600"
        svrtimeout = "3600"
        appflowlog = "DISABLED"
        cip = "ENABLED"
        cipheader = "ENABLED RL-SRC-IP"
        @uri.path = "/nitro/v1/config/servicegroup/"
        @uri.query = "action=add"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.servicegroup+json')
        @request.body = { :servicegroup => { :servicegroupname => "#{@sgservice_name}", :servicetype => "#{sg_type}", :state => "#{sg_state}", :cltTimeout => "#{clttimeout}", :svrtimeout => "#{svrtimeout}", :appflowlog => "#{appflowlog}" } }.to_json 

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                    @status_hash[:servicegroup] = "#{@sgservice_name}"
                else
                    print "fail!\n"
                    print "code: ", response.code.to_i, "\n"
                    print "body: ", response.body, "\n"
                end
        }

    end

    # here we add lb vservers.  the basic load balancing server in the netscaler.  this may be standalone (which requires)
    # an ipaddress (ipv46) be supplied or bound to a "cs vserver"
    def call_create_lbvserver(ipaddress="0.0.0.0", args = {})
        print "adding lb vserver..."
        @lbvserver_name = "vs-#{@servicename}-usa-qa-wh"
        # hard coded for testing
        ipaddress = "10.126.255.53"
        # hard coded for testing
        port = "80"
        # hard coded for testing
        http_or_ssl = "HTTP"
        @uri.path = "/nitro/v1/config/lbvserver/"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver+json')
        @request.body = { :lbvserver => { :name => "#{@lbvserver_name}", :servicetype => "#{http_or_ssl}", :ipv46 => "#{ipaddress}", :port => "#{port}", :persistencetype => "COOKIEINSERT", :timeout => "15", :lbmethod => "LRTM", :cltTimeout => "1800", :appflowlog => "DISABLED" } }.to_json 

        Net::HTTP.start(@uri.host, @uri.port) { |http|
            response = http.request(@request)
                if response.code == "201"
                    print "success!\n"
                    @status_hash[:lbvserver] = "@lbvserver_name"
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

    def call_create_monitor
        print "do nuttin"
    end

    def call_create_cspolicy
        print "do nuttin"
    end

    # generic binding function.  pass two objects 
    # return success or fail
    def call_bind_objects


        ### this is the server to servicegroup binding...no, it doesn't belong here
        @server_array.each { |x|  
        print "binding #{x} to the servicegroup..." 
        @uri.path = "/nitro/v1/config/servicegroup_servicegroupmember_binding/#{@sgservice_name}" 
        @uri.query = "action=bind"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.servicegroup_servicegroupmember_binding+json')
        @request.body = { :servicegroup_servicegroupmember_binding => { :servicegroupname => "#{@sgservice_name}", :servername => "#{x}", :port => "8080" } }.to_json 
        
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
        }


        ### this is the servicegroup to lbvserver binding, doesn't belong here
        print "binding #{@sgservice_name} to #{@lbvserver_name}..."
        @uri.path = "/nitro/v1/config/lbvserver_service_binding" 
        @uri.query = "action=bind"
        @request = Net::HTTP::Post.new(@uri)
        @request.basic_auth "#{@username}", "#{@password}"
        @request.add_field('Content-Type', 'application/vnd.com.citrix.netscaler.lbvserver_service_binding+json')
        @request.body = { :lbvserver_service_binding => { :name => "#{@lbvserver_name}", :servicename => "#{@sgservice_name}" } }.to_json 
        
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

    # generic UNBIND function.  pass two objects to unbind (order is important)
    # return success or fail
    def call_unbind_objects
        print "do nuttin"
    end


end
