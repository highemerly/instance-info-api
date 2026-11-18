module Api
  module V2
    # Public, read-only, no credentials: any origin may read it.
    class BaseController < ApplicationController
      include CacheHeaders

      before_action { response.set_header("Access-Control-Allow-Origin", "*") }
    end
  end
end
