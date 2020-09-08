Rails.application.routes.draw do
  scope 'stripe', as: 'stripe' do
    get 'payment/:id', to: 'reji/payment#show', as: 'payment'
    post 'webhook', to: 'reji/webhook#handle_webhook', as: 'webhook'
  end
end
