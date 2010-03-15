module PoolParty
  # Chef class bootstrapping chef-client.
  class ChefClient < Chef
    dsl_methods :server_url,:validation_token
    default_options(
      :version => "0.8",
      :validation_key => "/etc/chef/validation.pem"
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
openid_url         "#{openid_url}"
      EOE
      %w(search_url role_url remotefile_url template_url registration_url).each{|url|
        content+="#{url}   \"#{server_url}\"\n"
      }
      content+="validation_token  \"#{validation_token}\"\n" if validation_token
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
        "client_version" => version.to_s,
        "validation_key" => validation_key,
        "server_fqdn" => server.host,
        "server_port" => server.port.to_s }
        chef_hash["validation_token"] = validation_token if validation_token
      File.open(to,'w') {|f| f << JSON.pretty_generate("bootstrap" => { "chef" => chef_hash }, "recipes" => "bootstrap::client")}
      return to
    end
  end
end
