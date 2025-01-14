# frozen_string_literal: true

require "action_pack"
require "action_view"
require "action_controller"
require "sinatra/base"
require "sinatra/activerecord"
require "sinatra/flash"
require "sinatra/contrib/all"
require "rack/ssl"
require "json"
require "i18n"
require "will_paginate"
require "will_paginate/active_record"
require "sprockets"
require "sprockets-helpers"
require "securerandom"

require_relative "app/helpers/authentication_helpers"
require_relative "app/helpers/controller_helpers"
require_relative "app/repositories/user_repository"
require_relative "config/asset_pipeline"

require_relative "app/controllers/application_controller"
require_relative "app/controllers/debug_controller"
require_relative "app/controllers/feeds_controller"
require_relative "app/controllers/exports_controller"
require_relative "app/controllers/imports_controller"

module Rails
  def self.application
    OpenStruct.new(config: OpenStruct.new(cache_classes: true))
  end
end

I18n.load_path +=
  Dir[File.join(File.dirname(__FILE__), "config/locales", "*.yml").to_s]
I18n.config.enforce_available_locales = false
Time.zone = ENV.fetch("TZ", "UTC")

class Stringer < Sinatra::Base
  # need to exclude assets for sinatra assetpack, see https://github.com/stringer-rss/stringer/issues/112
  if ENV["ENFORCE_SSL"] == "true"
    use Rack::SSL, exclude: ->(env) { env["PATH_INFO"] =~ %r{^/(js|css|img)} }
  end

  extend Sinatra::ControllerHelpers

  register Sinatra::ActiveRecordExtension
  register Sinatra::Flash
  register Sinatra::Contrib
  register AssetPipeline

  configure do
    set :database_file, "config/database.yml"
    set :views, "app/views"
    set :public_dir, "app/public"
    set :root, File.dirname(__FILE__)

    enable :sessions
    set :session_secret, ENV["SECRET_TOKEN"] || SecureRandom.hex(32)
    enable :logging
    enable :method_override

    ActiveRecord::Base.include_root_in_json = false
  end

  helpers do
    include Sinatra::AuthenticationHelpers

    def render_partial(name, locals = {})
      erb "partials/_#{name}".to_sym, layout: false, locals: locals
    end

    def render_js_template(name)
      erb "js/templates/_#{name}.js".to_sym, layout: false
    end

    def render_js(name, locals = {})
      erb "js/#{name}.js".to_sym, layout: false, locals: locals
    end

    def t(*args, **kwargs)
      I18n.t(*args, **kwargs)
    end
  end

  before do
    I18n.locale = ENV["LOCALE"].blank? ? :en : ENV["LOCALE"].to_sym

    if !authenticated? && needs_authentication?(request.path)
      session[:redirect_to] = request.fullpath
      redirect "/login"
    end
  end

  get "/" do
    if UserRepository.setup_complete?
      redirect to("/news")
    else
      redirect to("/setup/password")
    end
  end

  rails_route(:get, "/debug", to: "debug#index")
  rails_route(:get, "/heroku", to: "debug#heroku")
  rails_route(:get, "/feeds", to: "feeds#index")
  rails_route(:get, "/feeds/:id/edit", to: "feeds#edit")
  rails_route(:put, "/feeds/:id", to: "feeds#update")
  rails_route(:delete, "/feeds/:id", to: "feeds#destroy")
  rails_route(:get, "/feeds/new", to: "feeds#new")
  rails_route(:post, "/feeds", to: "feeds#create")
  rails_route(:get, "/feeds/export", to: "exports#index")
  rails_route(:get, "/feeds/import", to: "imports#new")
  rails_route(:post, "/feeds/import", to: "imports#create")
end

require_relative "app/controllers/sinatra/stories_controller"
require_relative "app/controllers/sinatra/first_run_controller"
require_relative "app/controllers/sinatra/sessions_controller"
