module PoolParty
  # Chef class bootstrapping chef-client.
  class ChefClient < Chef
    CLIENT_VERSIONS=["0.7", "0.8"]
    dsl_methods :server_url,:validation_token
    default_options(
      :version => "0.8",
      :validation_key => "/etc/chef/validation.pem",
      :client_key => "/etc/chef/client.pem",
      :validation_client => "chef-validator",
      :validation_key_path => "/etc/chef/validation.pem"
    )
    
    def openid_url(url=nil)
      if url.nil?
        return @openid_url||= (u=URI.parse(server_url)
        u.port=4001
        openid_url u.to_s)
      else
        @openid_url=url 
      end
    end
    
    def roles(*roles)
      return @_roles||=[cloud.name] if roles.empty?
      @_roles=roles
    end

    def compile!
      build_tmp_dir
    end

    def node_bootstrap!(remote_instance)
      super(remote_instance)
      json_file=write_bootstrap_json
      remote_instance.scp :source => json_file, :destination => '/etc/chef/'
      if File.exists?(validation_key)
        remote_instance.scp :source => validation_key, :destination => validation_key_path
      else
        warn "Not copying validation key because it was not found" unless compat_version == "0.7"
      end
      remote_instance.ssh "`gem env |awk '$0 ~/EXECUTABLE DIRECTORY/{print $4}'`/chef-solo -j /etc/chef/bootstrap.json -r http://s3.amazonaws.com/chef-solo/bootstrap-latest.tar.gz"
    end

    private
    def after_initialized
      raise PoolPartyError.create("ChefArgumentMissing", "server_url must be specified!") unless server_url
    end
    def chef_cmd
      return "[ -x /usr/bin/svn ] && sv restart chef-client || /etc/init.d/chef-client restart"
    end
    # The NEW actual chef resolver.
    def build_tmp_dir
      base_directory = tmp_path/"etc"/"chef"
      FileUtils.rm_rf base_directory
      FileUtils.mkdir_p base_directory   
      puts "Creating the dna.json"
      attributes.to_dna [], base_directory/"dna.json", {:run_list => roles.map{|r| "role[#{r}]"} + _recipes.map{|r| "recipe[#{r}]"}}.merge(attributes.init_opts)
      write_client_dot_rb
    end
    
    def write_client_dot_rb(to=tmp_path/"etc"/"chef"/"client.rb")
      content = <<-EOE
log_level          :info
log_location       "/var/log/chef/client.log"
ssl_verify_mode    :verify_none
file_cache_path    "/var/cache/chef"
pid_file           "/var/run/chef/client.pid"
Chef::Log::Formatter.show_time = true
      EOE
      case chef_compat_version
      when "0.7"
        content+=%Q(openid_url         "#{openid_url}"\n)
        %w(search_url role_url remotefile_url template_url registration_url).each{|url|
          content+=%Q(#{url}   "#{server_url}"\n)
        }
        content+=%Q(validation_token  "#{validation_token}"\n) if validation_token
      when "0.8"
        content+= <<-EOE
chef_server_url         "#{server_url}"
validation_client_name  "#{validation_client}"
validation_key          "#{validation_key_path}"
client_key              "#{client_key}"
        EOE
      end
      File.open(to, "w") do |f|
        f << content
      end
    end

    def write_bootstrap_json(to=tmp_path/"etc/chef/bootstrap.json")
      server=URI.parse(server_url)
      chef_hash={
        "url_type" => server.scheme,
        "init_style" => "runit",
        "path" => "/var/lib/chef",
        "cache_path" => "/var/cache/chef",
        "client_version" => version,
        "validation_key" => validation_key_path,
        "server_fqdn" => server.host,
        "server_port" => server.port.to_s }
        chef_hash["validation_token"] = validation_token if validation_token
      File.open(to,'w') {|f| f << JSON.pretty_generate("bootstrap" => { "chef" => chef_hash }, "recipes" => "bootstrap::client")}
      return to
    end

    def chef_compat_version
        ver_ary=lambda {|s| s.split('.').map{|comp| comp.to_i}}
        CLIENT_VERSIONS.select{|ver| (ver_ary[ver] <=> ver_ary[version]) <= 0}.max{|a,b| ver_ary[a] <=> ver_ary[b]} || CLIENT_VERSIONS.min{|a,b| ver_ary[a] <=> ver_ary[b]}
    end

  end
end
