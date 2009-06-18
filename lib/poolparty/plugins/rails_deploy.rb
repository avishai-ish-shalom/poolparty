=begin rdoc
  Deploy a rails application using chef_deploy
  
  Usage:
      has_rails_deploy "app_name" do
        dir "/var/www"
        repo "git://github.com/auser/paparazzi.git"
        user "www-data"
        database_yml /path/to/database.yml # or a string
      end
    
    Sets up the filesystem structure (similar to capistrano deploy) and uses ezra's
    chef-deploy to deploy the application
=end
module PoolParty
  module Plugin
    class  RailsDeploy< Plugin
      
      dsl_methods :shared, :database_yml, :repo, :user, :user_dir
      
      default_options(
        :dir => "/var/www",
        :owner => "www-data",
        :group => "root",
        :install_sqlite => false,
        :migration_command => "rake db:migrate"
      )
      
      def loaded(o={}, &block)
        # TODO: Change to custom class
        raise DirectoryMissingError.new unless dir
        raise ReposMissingError.new unless repo
        
        require_rails_gems
        install_sqlite if o[:install_sqlite]
        
        create_directory_tree
        setup_database_yml
        call_deploy
        
        setup_shared_directory
        
      end
      private
      def require_rails_gems
        %w(rails actionmailer actionpack activerecord activesupport activeresource).each do |rails_gem|
          has_gem_package rails_gem
        end        
      end
      def install_sqlite
        has_gem_package "sqlite3-ruby"
      end
      def add_user(o)
        has_user user do
          comment "Rails Deploy user #{user}"
          home user_dir || "/var/www"
          shell "/sbin/nologin"
          password "x"
        end
      end
      def create_directory_tree
        has_directory dir, :mode => "0755", :owner => owner
        has_directory release_directory, :mode => "0755", :owner => owner
        has_directory "#{shared_directory}", :owner => owner, :mode => "0755"
        
        %w(config pids log system).each do |d|
          has_directory "#{shared_directory}/#{d}", :owner => owner, :mode => "0755"
        end
      end
      def setup_database_yml
        if database_yml
          has_file "#{shared_directory}/config/database.yml", :owner => owner do
            content ::File.file?(database_yml) ? open(database_yml).read : database_yml
          end
        end
      end
      def call_deploy
        has_package "git-core"
        dopts = dsl_options.choose {|k,v| [:repo, :user, :action].include?(k) }        
        has_chef_deploy dopts.merge(:name => "#{release_directory}", :user => owner)
      end
      def setup_shared_directory
        if shared
          shared.each do |sh|
            
            has_directory "#{shared_directory}/#{::File.dirname(sh)}", :owner => owner, :mode => "0755"
            
            has_exec "Create rails-deploy-#{git_name}-#{sh}", 
              :command => "cp #{current_directory}/#{sh} #{shared_directory}/#{sh} && chown -R #{owner} #{shared_directory}/#{sh}",
              :if_not => "test -f #{shared_directory}/#{sh}"
              
            has_symlink :name => "#{current_directory}/#{sh}", :to => "#{shared_directory}/#{sh}"
          end
        end
      end
      # HELPERS
      def git_name(n=nil)
        if n
          self.name = n
        else
          self.name ? self.name : ::File.basename(repo, ::File.extname(repo))
        end
      end
      
      def current_directory
        "#{release_directory}/current"
      end
      def shared_directory
        "#{release_directory}/shared"
      end
      def release_directory
        "#{dir}/#{git_name}"
      end
      
    end
  end
  
  class DirectoryMissingError < StandardError
    def initialize
      super("You must include the directory to deploy the rails app")
    end
  end
  class ReposMissingError < StandardError
    def initialize
      super("You must include the repo to deploy the rails app")
    end 
  end
end