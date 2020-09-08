Rails.application.routes.draw do
  scope 'stripe', as: 'stripe' do
    get 'payment/:id', to: 'payment#show', as: 'payment'
    post 'webhook', to: 'webhook#handle_webhook', as: 'webhook'
  end
end
