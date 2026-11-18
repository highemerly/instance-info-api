Rails.application.routes.draw do
  namespace 'api' do
    namespace 'v1' do
      get "instances/:name" => "instances#show", constraints: { name: /[^\/]+/ }
      get "health/live"     => "health#live"
      get "health/ready"    => "health#ready"
      get "health/sources"  => "health#sources"
    end
    namespace 'v2' do
      get "instances/:name" => "instances#show", constraints: { name: /[^\/]+/ }
      get "software"        => "software#index"
      get "stats"           => "stats#show"
    end
  end
end
