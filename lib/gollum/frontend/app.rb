require 'sinatra'
require 'gollum'
require 'mustache/sinatra'

require 'gollum/frontend/views/layout'
require 'gollum/frontend/views/editable'

module Precious
  class App < Sinatra::Base
    register Mustache::Sinatra

    dir = File.dirname(File.expand_path(__FILE__))

    # We want to serve public assets for now
    set :public,    "#{dir}/public"
    set :static,    true

    set :mustache, {
      # Tell mustache where the Views constant lives
      :namespace => Precious,

      # Mustache templates live here
      :templates => "#{dir}/templates",

      # Tell mustache where the views are
      :views => "#{dir}/views"
    }

    # Sinatra error handling
    configure :development, :staging do
      set :raise_errors, false
      set :show_exceptions, true
      set :dump_errors, true
      set :clean_trace, false
    end

    get '/' do
      show_page_or_file('Home')
    end

    get '/edit/:name' do
      @name = params[:name]
      wiki = Gollum::Wiki.new($path)
      if page = wiki.page(@name)
        @page = page
        @content = page.raw_data
        mustache :edit
      else
        mustache :create
      end
    end

    post '/edit/:name' do
      name   = params[:name]
      wiki   = Gollum::Wiki.new($path)
      page   = wiki.page(name)
      format = params[:format].intern
      name   = params[:rename] if params[:rename]

      wiki.update_page(page, name, format, params[:content], commit_message)

      redirect "/#{Gollum::Page.cname name}"
    end

    post '/create/:name' do
      name = params[:page]
      wiki = Gollum::Wiki.new($path)

      format = params[:format].intern

      begin
        wiki.write_page(name, format, params[:content], commit_message)
        redirect "/#{name}"
      rescue Gollum::DuplicatePageError => e
        @message = "Duplicate page: #{e.message}"
        mustache :error
      end
    end

    post '/preview' do
      format = params['wiki_format']
      data = params['text']
      wiki = Gollum::Wiki.new($path)
      wiki.preview_page("Preview", data, format).formatted_data
    end

    get '/history/:name' do
      @name     = params[:name]
      wiki      = Gollum::Wiki.new($path)
      @page     = wiki.page(@name)
      @page_num = [params[:page].to_i, 1].max
      @versions = @page.versions :page => @page_num
      mustache :history
    end

    post '/compare/:name' do
      @versions = params[:versions] || []
      if @versions.size < 2
        redirect "/history/#{params[:name]}"
      else
        redirect "/compare/%s/%s...%s" % [
          params[:name],
          @versions.last,
          @versions.first]
      end
    end

    get '/compare/:name/:version_list' do
      @name     = params[:name]
      @versions = params[:version_list].split(/\.{2,3}/)
      wiki      = Gollum::Wiki.new($path)
      @page     = wiki.page(@name)
      diffs     = wiki.repo.diff(@versions.first, @versions.last, @page.path)
      @diff     = diffs.first
      mustache :compare
    end

    get %r{/(.+?)/([0-9a-f]{40})} do
      name = params[:captures][0]
      wiki = Gollum::Wiki.new($path)
      if page = wiki.page(name, params[:captures][1])
        @page = page
        @name = name
        @content = page.formatted_data
        mustache :page
      else
        halt 404
      end
    end

    get '/*' do
      show_page_or_file(params[:splat].first)
    end

    def show_page_or_file(name)
      wiki = Gollum::Wiki.new($path)
      if page = wiki.page(name)
        @page = page
        @name = name
        @content = page.formatted_data
        mustache :page
      elsif file = wiki.file(name)
        file.raw_data
      else
        @name = name
        mustache :create
      end
    end

    def commit_message
      { :message => params[:message],
        :name    => `git config --get user.name `.strip,
        :email   => `git config --get user.email`.strip }
    end
  end
end
