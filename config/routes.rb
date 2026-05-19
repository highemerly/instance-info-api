Rails.application.routes.draw do
  namespace 'api' do
    namespace 'v1' do
      get "instances/:name" => "instances#show", constraints: { name: /[^\/]+/ }
      get "health/sources"  => "health#sources"
    end
  end
end
