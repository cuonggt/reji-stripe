# Rails Reji

- [Introduction](#introduction)
- [Installation](#installation)
- [Configuration](#configuration)
    - [Billable Model](#billable-model)
    - [API Keys](#api-keys)
    - [Currency Configuration](#currency-configuration)
- [Quickstart](#quickstart)
- [Customers](#customers)
    - [Retrieving Customers](#retrieving-customers)
    - [Creating Customers](#creating-customers)
    - [Updating Customers](#updating-customers)
    - [Billing Portal](#billing-portal)
- [Payment Methods](#payment-methods)
    - [Storing Payment Methods](#storing-payment-methods)
    - [Retrieving Payment Methods](#retrieving-payment-methods)
    - [Determining If A User Has A Payment Method](#check-for-a-payment-method)
    - [Updating The Default Payment Method](#updating-the-default-payment-method)
    - [Adding Payment Methods](#adding-payment-methods)
    - [Deleting Payment Methods](#deleting-payment-methods)
- [Subscriptions](#subscriptions)
    - [Creating Subscriptions](#creating-subscriptions)
    - [Checking Subscription Status](#checking-subscription-status)
    - [Changing Plans](#changing-plans)
    - [Subscription Quantity](#subscription-quantity)
    - [Multiplan Subscriptions](#multiplan-subscriptions)
    - [Subscription Taxes](#subscription-taxes)
    - [Subscription Anchor Date](#subscription-anchor-date)
    - [Cancelling Subscriptions](#cancelling-subscriptions)
    - [Resuming Subscriptions](#resuming-subscriptions)
- [Subscription Trials](#subscription-trials)
    - [With Payment Method Up Front](#with-payment-method-up-front)
    - [Without Payment Method Up Front](#without-payment-method-up-front)
    - [Extending Trials](#extending-trials)
- [Handling Stripe Webhooks](#handling-stripe-webhooks)
    - [Defining Webhook Event Handlers](#defining-webhook-event-handlers)
    - [Failed Subscriptions](#handling-failed-subscriptions)
    - [Verifying Webhook Signatures](#verifying-webhook-signatures)
- [Single Charges](#single-charges)
    - [Simple Charge](#simple-charge)
    - [Charge With Invoice](#charge-with-invoice)
    - [Refunding Charges](#refunding-charges)
- [Invoices](#invoices)
    - [Retrieving Invoices](#retrieving-invoices)
    - [Generating Invoice PDFs](#generating-invoice-pdfs)
- [Handling Failed Payments](#handling-failed-payments)
- [Stripe SDK](#stripe-sdk)
- [Testing](#testing)
- [License](#license)

<a name="introduction"></a>
## Introduction

Reji provides an expressive, fluent interface to [Stripe's](https://stripe.com) subscription billing services for your Rails applications. It handles almost all of the boilerplate subscription billing code you are dreading writing. In addition to basic subscription management, Reji can handle coupons, swapping subscription, subscription "quantities", cancellation grace periods, and even generate invoice PDFs.

<a name="installation"></a>
## Installation

Reji is a Rails gem tested against Rails `>= 5.0` and Ruby `>= 2.4.0`.

> To prevent breaking changes, Reji uses a fixed Stripe API version. Reji currently utilizes Stripe API version `2020-08-27`. The Stripe API version will be updated on minor releases in order to make use of new Stripe features and improvements.

You can add it to your Gemfile with:

```bash
gem 'reji'
```

Run the bundle command to install it.

> To ensure Reji properly handles all Stripe events, remember to [set up Reji's webhook handling](#handling-stripe-webhooks).

After you install Reji, you need to run the generator:

```bash
rails generate reji:install
```

The Reji install generator:

* Creates an initializer file to allow further configuration.
* Creates migration files that add several columns to your `users` table as well as create a new `subscriptions` table to hold all of your customer's subscriptions.

#### Database Migrations

Remember to migrate your database after installing the gem. The Reji migrations will add several columns to your `users` table as well as create a new `subscriptions` table to hold all of your customer's subscriptions:

```bash
rails db:migrate
```

> Stripe recommends that any column used for storing Stripe identifiers should be case-sensitive. Therefore, you should ensure the column collation for the `stripe_id` column is set to, for example, `utf8_bin` in MySQL. More info can be found [in the Stripe documentation](https://stripe.com/docs/upgrades#what-changes-does-stripe-consider-to-be-backwards-compatible).

<a name="configuration"></a>
## Configuration

<a name="billable-model"></a>
### Billable Model

Before using Reji, add the `Billable` concern to your model definition. This concern provides various methods to allow you to perform common billing tasks, such as creating subscriptions, applying coupons, and updating payment method information:

```ruby
class User < ApplicationRecord
  include Reji::Billable
end
```

Reji assumes your Billable model will be the `User` class. If you wish to change this you can specify a different model by setting the `REJI_MODEL` environment variable:

```sh
REJI_MODEL=User
```

> If you're using a model other than `User` model, you'll need to publish and alter the [migrations](#installation) provided to match your alternative model's table name.

<a name="api-keys"></a>
### API Keys

Next, you should configure your Stripe keys in your environment variables. You can retrieve your Stripe API keys from the Stripe control panel.

```sh
STRIPE_KEY=your-stripe-key
STRIPE_SECRET=your-stripe-secret
```

<a name="currency-configuration"></a>
### Currency Configuration

The default Reji currency is United States Dollars (USD). You can change the default currency by setting the `REJI_CURRENCY` environment variable:

```sh
REJI_CURRENCY=eur
```

<a name="quickstart"></a>
## Quickstart

With Reji, subscriptions will be much simpler in your Rails application:

```ruby
class Api::SubscriptionController < ApplicationController
  def store
    begin
      current_user.new_subscription('default', params[:stripe_plan]).add
    rescue Stripe::InvalidRequestError => e
      render json: { stripe_plan: e.error.message }, status: 422
    end
  end

  def update
    begin
      current_user.subscription('default').swap(params[:stripe_plan])
    rescue Stripe::InvalidRequestError => e
      render json: { stripe_plan: e.error.message }, status: 422
    end
  end

  def destroy
    current_user.subscription('default').cancel
  end
end
```

<a name="customers"></a>
## Customers

<a name="retrieving-customers"></a>
### Retrieving Customers

You can retrieve a customer by their Stripe ID using the `Reji.find_billable` method. This will return an instance of the Billable model:

```ruby
user = Reji.find_billable(stripe_id)
```

<a name="creating-customers"></a>
### Creating Customers

Occasionally, you may wish to create a Stripe customer without beginning a subscription. You may accomplish this using the `create_as_stripe_customer` method:

```ruby
stripe_customer = user.create_as_stripe_customer
```

Once the customer has been created in Stripe, you may begin a subscription at a later date. You can also use an optional `options` array to pass in any additional parameters which are supported by the Stripe API:

```ruby
stripe_customer = user.create_as_stripe_customer(options)
```

You may use the `as_stripe_customer` method if you want to return the customer object if the billable entity is already a customer within Stripe:

```ruby
stripe_customer = user.as_stripe_customer
```

The `create_or_get_stripe_customer` method may be used if you want to return the customer object but are not sure whether the billable entity is already a customer within Stripe. This method will create a new customer in Stripe if one does not already exist:

```ruby
stripe_customer = user.create_or_get_stripe_customer
```

<a name="updating-customers"></a>
### Updating Customers

Occasionally, you may wish to update the Stripe customer directly with additional information. You may accomplish this using the `update_stripe_customer` method:

```ruby
stripe_customer = user.update_stripe_customer(options)
```

<a name="billing-portal"></a>
### Billing Portal

Stripe offers [an easy way to set up a billing portal](https://stripe.com/docs/billing/subscriptions/customer-portal) so your customer can manage their subscription, payment methods, and view their billing history. You can redirect your users to the billing portal using the `billing_portal_url` method from a controller:

```ruby
def billing_portal
  redirect_to user.billing_portal_url
end
```

By default, when the user is finished managing their subscription, they can return to the root `/` url of your application. You may provide a custom URL the user should return to by passing the URL as an argument to the `billing_portal_url` method:

```ruby
def billing_portal
  redirect_to user.billing_portal_url('/billing')
end
```

<a name="payment-methods"></a>
## Payment Methods

<a name="storing-payment-methods"></a>
### Storing Payment Methods

In order to create subscriptions or perform "one off" charges with Stripe, you will need to store a payment method and retrieve its identifier from Stripe. The approach used to accomplish differs based on whether you plan to use the payment method for subscriptions or single charges, so we will examine both below.

#### Payment Methods For Subscriptions

When storing credit cards to a customer for future use, the Stripe Setup Intents API must be used to securely gather the customer's payment method details. A "Setup Intent" indicates to Stripe the intention to charge a customer's payment method. Reji's `Billable` concern includes the `create_setup_intent` to easily create a new Setup Intent. You should call this method from a controller that will render the form which gathers your customer's payment method details:

```ruby
@intent = user.create_setup_intent
render 'update-payment-method'
```

After you have created the Setup Intent and passed it to the view, you should attach its secret to the element that will gather the payment method. For example, consider this "update payment method" form:

```html
<input id="card-holder-name" type="text">

<!-- Stripe Elements Placeholder -->
<div id="card-element"></div>

<button id="card-button" data-secret="<%= intent.client_secret %>">
    Update Payment Method
</button>
```

Next, the Stripe.js library may be used to attach a Stripe Element to the form and securely gather the customer's payment details:

```html
<script src="https://js.stripe.com/v3/"></script>

<script>
    const stripe = Stripe('stripe-public-key');

    const elements = stripe.elements();
    const cardElement = elements.create('card');

    cardElement.mount('#card-element');
</script>
```

Next, the card can be verified and a secure "payment method identifier" can be retrieved from Stripe using [Stripe's `confirmCardSetup` method](https://stripe.com/docs/js/setup_intents/confirm_card_setup):

```js
const cardHolderName = document.getElementById('card-holder-name');
const cardButton = document.getElementById('card-button');
const clientSecret = cardButton.dataset.secret;

cardButton.addEventListener('click', async (e) => {
    const { setupIntent, error } = await stripe.confirmCardSetup(
        clientSecret, {
            payment_method: {
                card: cardElement,
                billing_details: { name: cardHolderName.value }
            }
        }
    );

    if (error) {
        // Display "error.message" to the user...
    } else {
        // The card has been verified successfully...
    }
});
```

After the card has been verified by Stripe, you may pass the resulting `setupIntent.payment_method` identifier to your Rails application, where it can be attached to the customer. The payment method can either be [added as a new payment method](#adding-payment-methods) or [used to update the default payment method](#updating-the-default-payment-method). You can also immediately use the payment method identifier to [create a new subscription](#creating-subscriptions).

> If you would like more information about Setup Intents and gathering customer payment details please [review this overview provided by Stripe](https://stripe.com/docs/payments/save-and-reuse#ruby).

#### Payment Methods For Single Charges

Of course, when making a single charge against a customer's payment method we'll only need to use a payment method identifier a single time. Due to Stripe limitations, you may not use the stored default payment method of a customer for single charges. You must allow the customer to enter their payment method details using the Stripe.js library. For example, consider the following form:

```html
<input id="card-holder-name" type="text">

<!-- Stripe Elements Placeholder -->
<div id="card-element"></div>

<button id="card-button">
    Process Payment
</button>
```

Next, the Stripe.js library may be used to attach a Stripe Element to the form and securely gather the customer's payment details:

```html
<script src="https://js.stripe.com/v3/"></script>

<script>
    const stripe = Stripe('stripe-public-key');

    const elements = stripe.elements();
    const cardElement = elements.create('card');

    cardElement.mount('#card-element');
</script>
```

Next, the card can be verified and a secure "payment method identifier" can be retrieved from Stripe using [Stripe's `createPaymentMethod` method](https://stripe.com/docs/stripe-js/reference#stripe-create-payment-method):

```js
const cardHolderName = document.getElementById('card-holder-name');
const cardButton = document.getElementById('card-button');

cardButton.addEventListener('click', async (e) => {
    const { paymentMethod, error } = await stripe.createPaymentMethod(
        'card', cardElement, {
            billing_details: { name: cardHolderName.value }
        }
    );

    if (error) {
        // Display "error.message" to the user...
    } else {
        // The card has been verified successfully...
    }
});
```

If the card is verified successfully, you may pass the `paymentMethod.id` to your Rails application and process a [single charge](#simple-charge).

<a name="retrieving-payment-methods"></a>
### Retrieving Payment Methods

The `payment_methods` method on the Billable model instance returns a collection of `Reji::PaymentMethod` instances:

```ruby
payment_methods = user.payment_methods
```

To retrieve the default payment method, the `default_payment_method` method may be used:

```ruby
payment_method = user.default_payment_method
```

You can also retrieve a specific payment method that is owned by the Billable model using the `find_payment_method` method:

```ruby
payment_method = user.find_payment_method(payment_method_id)
```

<a name="check-for-a-payment-method"></a>
### Determining If A User Has A Payment Method

To determine if a Billable model has a default payment method attached to their account, use the `has_default_payment_method` method:

```ruby
if user.has_default_payment_method
  #
end
```

To determine if a Billable model has at least one payment method attached to their account, use the `has_payment_method` method:

```ruby
if user.has_payment_method
  #
end
```

<a name="updating-the-default-payment-method"></a>
### Updating The Default Payment Method

The `update_default_payment_method` method may be used to update a customer's default payment method information. This method accepts a Stripe payment method identifier and will assign the new payment method as the default billing payment method:

```ruby
user.update_default_payment_method(payment_method)
```

To sync your default payment method information with the customer's default payment method information in Stripe, you may use the `update_default_payment_method_from_stripe` method:

```ruby
user.update_default_payment_method_from_stripe
```

> The default payment method on a customer can only be used for invoicing and creating new subscriptions. Due to limitations from Stripe, it may not be used for single charges.

<a name="adding-payment-methods"></a>
### Adding Payment Methods

To add a new payment method, you may call the `add_payment_method` method on the billable user, passing the payment method identifier:

```ruby
user.add_payment_method(payment_method)
```

> To learn how to retrieve payment method identifiers please review the [payment method storage documentation](#storing-payment-methods).

<a name="deleting-payment-methods"></a>
### Deleting Payment Methods

To delete a payment method, you may call the `delete` method on the `Reji::PaymentMethod` instance you wish to delete:

```ruby
payment_method.delete
```

The `delete_payment_methods` method will delete all of the payment method information for the Billable model:

```ruby
user.delete_payment_methods
```

> If a user has an active subscription, you should prevent them from deleting their default payment method.

<a name="subscriptions"></a>
## Subscriptions

<a name="creating-subscriptions"></a>
### Creating Subscriptions

To create a subscription, first retrieve an instance of your billable model, which typically will be an instance of `User`. Once you have retrieved the model instance, you may use the `new_subscription` method to create the model's subscription:

```ruby
user = User.find(1)
user.new_subscription('default', 'price_premium').create(payment_method)
```

The first argument passed to the `new_subscription` method should be the name of the subscription. If your application only offers a single subscription, you might call this `default` or `primary`. The second argument is the specific plan the user is subscribing to. This value should correspond to the plan's price identifier in Stripe.

The `create` method, which accepts [a Stripe payment method identifier](#storing-payment-methods) or Stripe `PaymentMethod` object, will begin the subscription as well as update your database with the customer ID and other relevant billing information.

> Passing a payment method identifier directly to the `create` subscription method will also automatically add it to the user's stored payment methods.

#### Quantities

If you would like to set a specific quantity for the plan when creating the subscription, you may use the `quantity` method:

```ruby
user.new_subscription('default', 'price_monthly')
  .quantity(5)
  .create(payment_method)
```

#### Additional Details

If you would like to specify additional customer or subscription details, you may do so by passing them as the second and third arguments to the `create` method:

```ruby
user.new_subscription('default', 'price_monthly').create(payment_method, {
  :email => email,
}, {
  :metadata => {:note => 'Some extra information.'},
})
```

To learn more about the additional fields supported by Stripe, check out Stripe's documentation on [customer creation](https://stripe.com/docs/api#create_customer) and [subscription creation](https://stripe.com/docs/api/subscriptions/create).

#### Coupons

If you would like to apply a coupon when creating the subscription, you may use the `with_coupon` method:

```ruby
user.new_subscription('default', 'price_monthly')
  .with_coupon('code')
  .create(payment_method)
```

#### Adding Subscriptions

If you would like to add a subscription to a customer who already has a default payment method set you can use the `add` method when using the `new_subscription` method:

```ruby
user = User.find(1)
user.new_subscription('default', 'price_premium').add
```

<a name="checking-subscription-status"></a>
### Checking Subscription Status

Once a user is subscribed to your application, you may easily check their subscription status using a variety of convenient methods. First, the `subscribed` method returns `true` if the user has an active subscription, even if the subscription is currently within its trial period:

```ruby
if user.subscribed('default')
  #
end
```

If you would like to determine if a user is still within their trial period, you may use the `on_trial` method. This method can be useful for displaying a warning to the user that they are still on their trial period:

```ruby
if user.subscription('default').on_trial
  #
end
```

The `subscribed_to_plan` method may be used to determine if the user is subscribed to a given plan based on a given Stripe Price ID. In this example, we will determine if the user's `default` subscription is actively subscribed to the `monthly` plan:

```ruby
if user.subscribed_to_plan('price_monthly', 'default')
  #
end
```

By passing an array to the `subscribed_to_plan` method, you may determine if the user's `default` subscription is actively subscribed to the `monthly` or the `yearly` plan:

```ruby
if user.subscribed_to_plan(['price_monthly', 'price_yearly'], 'default')
  #
end
```

The `recurring` method may be used to determine if the user is currently subscribed and is no longer within their trial period:

```ruby
if user.subscription('default').recurring
  #
end
```

#### Cancelled Subscription Status

To determine if the user was once an active subscriber, but has cancelled their subscription, you may use the `cancelled` method:

```ruby
if user.subscription('default').cancelled
  #
end
```

You may also determine if a user has cancelled their subscription, but are still on their "grace period" until the subscription fully expires. For example, if a user cancels a subscription on March 5th that was originally scheduled to expire on March 10th, the user is on their "grace period" until March 10th. Note that the `subscribed` method still returns `true` during this time:

```ruby
if user.subscription('default').on_grace_period
  #
end
```

To determine if the user has cancelled their subscription and is no longer within their "grace period", you may use the `ended` method:

```ruby
if user.subscription('default').ended
  #
end
```

#### Subscription Scopes

Most subscription states are also available as query scopes so that you may easily query your database for subscriptions that are in a given state:

```ruby
# Get all active subscriptions...
subscriptions = Reji::Subscription.active

# Get all of the cancelled subscriptions for a user...
subscriptions = user.subscriptions.cancelled
```

A complete list of available scopes is available below:

```ruby
Reji::Subscription.active
Reji::Subscription.cancelled
Reji::Subscription.ended
Reji::Subscription.incomplete
Reji::Subscription.not_cancelled
Reji::Subscription.not_on_grace_period
Reji::Subscription.not_on_trial
Reji::Subscription.on_grace_period
Reji::Subscription.on_trial
Reji::Subscription.past_due
Reji::Subscription.recurring
```

<a name="incomplete-and-past-due-status"></a>
#### Incomplete and Past Due Status

If a subscription requires a secondary payment action after creation the subscription will be marked as `incomplete`. Subscription statuses are stored in the `stripe_status` column of Reji's `subscriptions` database table.

Similarly, if a secondary payment action is required when swapping plans the subscription will be marked as `past_due`. When your subscription is in either of these states it will not be active until the customer has confirmed their payment. Checking if a subscription has an incomplete payment can be done using the `has_incomplete_payment` method on the Billable model or a subscription instance:

```ruby
if user.has_incomplete_payment('default')
  #
end

if user.subscription('default').has_incomplete_payment
  #
end
```

When a subscription has an incomplete payment, you should direct the user to Reji's payment confirmation page, passing the `latest_payment` identifier. You may use the `latest_payment` method available on subscription instance to retrieve this identifier:

```html
<a href="/stripe/payment/<%= subscription.latest_payment.id %>">
    Please confirm your payment.
</a>
```

If you would like the subscription to still be considered active when it's in a `past_due` state, you may use the `keep_past_due_subscriptions_active` method provided by Reji:

```ruby
Reji.keep_past_due_subscriptions_active
```

> When a subscription is in an `incomplete` state it cannot be changed until the payment is confirmed. Therefore, the `swap` and `update_quantity` methods will throw an exception when the subscription is in an `incomplete` state.

<a name="changing-plans"></a>
### Changing Plans

After a user is subscribed to your application, they may occasionally want to change to a new subscription plan. To swap a user to a new subscription, pass the plan's price identifier to the `swap` method:

```ruby
user = User.find(1)
user.subscription('default').swap('provider-price-id')
```

If the user is on trial, the trial period will be maintained. Also, if a "quantity" exists for the subscription, that quantity will also be maintained.

If you would like to swap plans and cancel any trial period the user is currently on, you may use the `skip_trial` method:

```ruby
user.subscription('default')
  .skip_trial
  .swap('provider-price-id')
```

If you would like to swap plans and immediately invoice the user instead of waiting for their next billing cycle, you may use the `swap_and_invoice` method:

```ruby
user = User.find(1)
user.subscription('default').swap_and_invoice('provider-price-id')
```

#### Prorations

By default, Stripe prorates charges when swapping between plans. The `no_prorate` method may be used to update the subscription's without prorating the charges:

```ruby
user.subscription('default').no_prorate.swap('provider-price-id')
```

For more information on subscription proration, consult the [Stripe documentation](https://stripe.com/docs/billing/subscriptions/prorations).

> Executing the `no_prorate` method before the `swap_and_invoice` method will have no affect on proration. An invoice will always be issued.

<a name="subscription-quantity"></a>
### Subscription Quantity

Sometimes subscriptions are affected by "quantity". For example, your application might charge $10 per month **per user** on an account. To easily increment or decrement your subscription quantity, use the `increment_quantity` and `decrement_quantity` methods:

```ruby
user = User.find(1)

user.subscription('default').increment_quantity

# Add five to the subscription's current quantity...
user.subscription('default').increment_quantity(5)

user.subscription('default').decrement_quantity

# Subtract five to the subscription's current quantity...
user.subscription('default').decrement_quantity(5)
```

Alternatively, you may set a specific quantity using the `update_quantity` method:

```ruby
user.subscription('default').update_quantity(10)
```

The `no_prorate` method may be used to update the subscription's quantity without prorating the charges:

```ruby
user.subscription('default').no_prorate.update_quantity(10)
```

For more information on subscription quantities, consult the [Stripe documentation](https://stripe.com/docs/subscriptions/quantities).

> Please note that when working with multiplan subscriptions, an extra "plan" parameter is required for the above quantity methods.

<a name="multiplan-subscriptions"></a>
### Multiplan Subscriptions

[Multiplan subscriptions](https://stripe.com/docs/billing/subscriptions/multiplan) allow you to assign multiple billing plans to a single subscription. For example, imagine you are building a customer service "helpdesk" application that has a base subscription of $10 per month, but offers a live chat add-on plan for an additional $15 per month:

```ruby
user = User.find(1)
user.new_subscription('default', [
  'price_monthly',
  'chat-plan',
]).create(payment_method)
```

Now the customer will have two plans on their `default` subscription. Both plans will be charged for on their respective billing intervals. You can also use the `quantity` method to indicate the specific quantity for each plan:

```ruby
user = User.find(1)
user.new_subscription('default', ['price_monthly', 'chat-plan'])
  .quantity(5, 'chat-plan')
  .create(payment_method)
```

Or, you may dynamically add the extra plan and its quantity using the `plan` method:

```ruby
user = User.find(1)
user.new_subscription('default', 'price_monthly')
  .plan('chat-plan', 5)
  .create(payment_method)
```

Alternatively, you may add a new plan to an existing subscription at a later time:

```ruby
user = User.find(1)
user.subscription('default').add_plan('chat-plan')
```

The example above will add the new plan and the customer will be billed for it on their next billing cycle. If you would like to bill the customer immediately you may use the `add_plan_and_invoice` method:

```ruby
user.subscription('default').add_plan_and_invoice('chat-plan')
```

If you would like to add a plan with a specific quantity, you can pass the quantity as the second parameter of the `add_plan` or `add_plan_and_invoice` methods:

```ruby
user = User.find(1)
user.subscription('default').add_plan('chat-plan', 5)
```

You may remove plans from subscriptions using the `remove_plan` method:

```ruby
user.subscription('default').remove_plan('chat-plan')
```

> You may not remove the last plan on a subscription. Instead, you should simply cancel the subscription.

### Swapping

You may also change the plans attached to a multiplan subscription. For example, imagine you're on a `basic-plan` subscription with a `chat-plan` add-on and you want to upgrade to the `pro-plan` plan:

```ruby
user = User.find(1)
user.subscription('default').swap(['pro-plan', 'chat-plan'])
```

When executing the code above, the underlying subscription item with the `basic-plan` is deleted and the one with the `chat-plan` is preserved. Additionally, a new subscription item for the new `pro-plan` is created.

If you want to swap a single plan on a subscription, you may do so using the `swap` method on the subscription item itself. This approach is useful if you, for example, want to preserve all of the existing metadata on the subscription item.

```ruby
user = User.find(1)
user.subscription('default')
  .find_item_or_fail('basic-plan')
  .swap('pro-plan')
```

#### Proration

By default, Stripe will prorate charges when adding or removing plans from a subscription. If you would like to make a plan adjustment without proration, you should chain the `no_prorate` method onto your plan operation:

```ruby
user.subscription('default').no_prorate.remove_plan('chat-plan')
```

#### Quantities

If you would like to update quantities on individual subscription plans, you may do so using the [existing quantity methods](#subscription-quantity) and passing the name of the plan as an additional argument to the method:

```ruby
user = User.find(1)

user.subscription('default').increment_quantity(5, 'chat-plan')

user.subscription('default').decrement_quantity(3, 'chat-plan')

user.subscription('default').update_quantity(10, 'chat-plan')
```

> When you have multiple plans set on a subscription the `stripe_plan` and `quantity` attributes on the `Subscription` model will be `null`. To access the individual plans, you should use the `items` relationship available on the `Subscription` model.

#### Subscription Items

When a subscription has multiple plans, it will have multiple subscription "items" stored in your database's `subscription_items` table. You may access these via the `items` relationship on the subscription:

```ruby
user = User.find(1)

subscription_item = user.subscription('default').items.first

# Retrieve the Stripe plan and quantity for a specific item...
stripe_plan = subscription_item.stripe_plan
quantity = subscription_item.quantity
```

You can also retrieve a specific plan using the `find_item_or_fail` method:

```ruby
user = User.find(1)
subscription_item = user.subscription('default').find_item_or_fail('chat-plan')
```

<a name="subscription-taxes"></a>
### Subscription Taxes

To specify the tax rates a user pays on a subscription, implement the `tax_rates` method on your billable model, and return an array with the Tax Rate IDs. You can define these tax rates in [your Stripe dashboard](https://dashboard.stripe.com/test/tax-rates):

```ruby
def tax_rates
  ['tax-rate-id']
end
```

The `tax_rates` method enables you to apply a tax rate on a model-by-model basis, which may be helpful for a user base that spans multiple countries and tax rates. If you're working with multiplan subscriptions you can define different tax rates for each plan by implementing a `plan_tax_rates` method on your billable model:

```ruby
def plan_tax_rates
  [
    'plan-id' => ['tax-rate-id'],
  ]
end
```

> The `tax_rates` method only applies to subscription charges. If you use Reji to make "one off" charges, you will need to manually specify the tax rate at that time.

#### Syncing Tax Rates

When changing the hard-coded Tax Rate IDs returned by the `tax_rates` method, the tax settings on any existing subscriptions for the user will remain the same. If you wish to update the tax value for existing subscriptions with the returned `tax_tax_rates` values, you should call the `sync_tax_rates` method on the user's subscription instance:

```ruby
user.subscription('default').sync_tax_rates
```

This will also sync any subscription item tax rates so make sure you also properly change the `plan_tax_rates` method.

#### Tax Exemption

Reji also offers methods to determine if the customer is tax exempt by calling the Stripe API. The `is_not_tax_exempt`, `is_tax_exempt`, and `reverse_charge_applies` methods are available on the billable model:

```ruby
user = User.find(1)
user.is_tax_exempt
user.is_not_tax_exempt
user.reverse_charge_applies
```

These methods are also available on any `Reji::Invoice` object. However, when calling these methods on an `Invoice` object the methods will determine the exemption status at the time the invoice was created.

<a name="subscription-anchor-date"></a>
### Subscription Anchor Date

By default, the billing cycle anchor is the date the subscription was created, or if a trial period is used, the date that the trial ends. If you would like to modify the billing anchor date, you may use the `anchor_billing_cycle_on` method:

```ruby
user = User.find(1)

anchor = Time.now.at_beginning_of_month.next_month

user.new_subscription('default', 'price_premium')
  .anchor_billing_cycle_on(anchor.to_i)
  .create(payment_method)
```

For more information on managing subscription billing cycles, consult the [Stripe billing cycle documentation](https://stripe.com/docs/billing/subscriptions/billing-cycle)

<a name="cancelling-subscriptions"></a>
### Cancelling Subscriptions

To cancel a subscription, call the `cancel` method on the user's subscription:

```ruby
user.subscription('default').cancel
```

When a subscription is cancelled, Reji will automatically set the `ends_at` column in your database. This column is used to know when the `subscribed` method should begin returning `false`. For example, if a customer cancels a subscription on March 1st, but the subscription was not scheduled to end until March 5th, the `subscribed` method will continue to return `true` until March 5th.

You may determine if a user has cancelled their subscription but are still on their "grace period" using the `on_grace_period` method:

```ruby
if user.subscription('default').on_grace_period
  #
end
```

If you wish to cancel a subscription immediately, call the `cancel_now` method on the user's subscription:

```ruby
user.subscription('default').cancel_now
```

<a name="resuming-subscriptions"></a>
### Resuming Subscriptions

If a user has cancelled their subscription and you wish to resume it, use the `resume` method. The user **must** still be on their grace period in order to resume a subscription:

```ruby
user.subscription('default').resume
```

If the user cancels a subscription and then resumes that subscription before the subscription has fully expired, they will not be billed immediately. Instead, their subscription will be re-activated, and they will be billed on the original billing cycle.

<a name="subscription-trials"></a>
## Subscription Trials

<a name="with-payment-method-up-front"></a>
### With Payment Method Up Front

If you would like to offer trial periods to your customers while still collecting payment method information up front, you should use the `trial_days` method when creating your subscriptions:

```ruby
user = User.find(1)
user.new_subscription('default', 'price_monthly')
  .trial_days(10)
  .create(payment_method)
```

This method will set the trial period ending date on the subscription record within the database, as well as instruct Stripe to not begin billing the customer until after this date. When using the `trial_days` method, Reji will overwrite any default trial period configured for the plan in Stripe.

> If the customer's subscription is not cancelled before the trial ending date they will be charged as soon as the trial expires, so you should be sure to notify your users of their trial ending date.

The `trial_until` method allows you to provide a `Time` instance to specify when the trial period should end:

```ruby
user.new_subscription('default', 'price_monthly')
  .trial_until(Time.now + 10.days)
  .create(payment_method)
```

You may determine if the user is within their trial period using either the `on_trial` method of the user instance, or the `on_trial` method of the subscription instance. The two examples below are identical:

```ruby
if user.on_trial('default')
  #
end

if user.subscription('default').on_trial
  #
end
```

#### Defining Trial Days In Stripe / Reji

You may choose to define how many trial days your plan's receive in the Stripe dashboard or always pass them explicitly using Reji. If you choose to define your plan's trial days in Stripe you should be aware that new subscriptions, including new subscriptions for a customer that had a subscription in the past, will always receive a trial period unless you explicitly call the `trial_days(0)` method.

<a name="without-payment-method-up-front"></a>
### Without Payment Method Up Front

If you would like to offer trial periods without collecting the user's payment method information up front, you may set the `trial_ends_at` column on the user record to your desired trial ending date. This is typically done during user registration:

```ruby
user = User.create({
  # Populate other user properties...
  :trial_ends_at => Time.now + 10.days,
})
```

Reji refers to this type of trial as a "generic trial", since it is not attached to any existing subscription. The `on_trial` method on the `User` instance will return `true` if the current date is not past the value of `trial_ends_at`:

```ruby
if user.on_trial
  # User is within their trial period...
end
```

You may also use the `on_generic_trial` method if you wish to know specifically that the user is within their "generic" trial period and has not created an actual subscription yet:

```ruby
if user.on_generic_trial
  # User is within their "generic" trial period...
end
```

Once you are ready to create an actual subscription for the user, you may use the `new_subscription` method as usual:

```ruby
user = User.find(1)
user.new_subscription('default', 'price_monthly').create(payment_method)
```

<a name="extending-trials"></a>
### Extending Trials

The `extend_trial` method allows you to extend the trial period of a subscription after it's been created:

```ruby
# End the trial 7 days from now...
subscription.extend_trial(
  Time.now + 7.days
)

# Add an additional 5 days to the trial...
subscription.extend_trial(
  Time.at(subscription.trial_ends_at) + 5.days
)
```

If the trial has already expired and the customer is already being billed for the subscription, you can still offer them an extended trial. The time spent within the trial period will be deducted from the customer's next invoice.

<a name="handling-stripe-webhooks"></a>
## Handling Stripe Webhooks

> You may use [the Stripe CLI](https://stripe.com/docs/stripe-cli) to help test webhooks during local development.

Stripe can notify your application of a variety of events via webhooks. By default, a route that points to Reji's webhook controller is configured. This controller will handle all incoming webhook requests.

By default, this controller will automatically handle cancelling subscriptions that have too many failed charges (as defined by your Stripe settings), customer updates, customer deletions, subscription updates; however, as we'll soon discover, you can extend this controller to handle any webhook event you like.

To ensure your application can handle Stripe webhooks, be sure to configure the webhook URL in the Stripe control panel. By default, Reji's webhook controller listens to the `/stripe/webhook` URL path. The full list of all webhooks you should configure in the Stripe control panel are:

- `customer.subscription.updated`
- `customer.subscription.deleted`
- `customer.updated`
- `customer.deleted`

> Make sure you protect incoming requests with Reji's included [webhook signature verification](/docs/{{version}}/billing#verifying-webhook-signatures) middleware.

<a name="defining-webhook-event-handlers"></a>
### Defining Webhook Event Handlers

Reji automatically handles subscription cancellation on failed charges, but if you have additional webhook events you would like to handle, extend the Webhook controller. Your method names should correspond to Reji's expected convention, specifically, methods should be prefixed with `handle` and the "snake case" name of the webhook you wish to handle. For example, if you wish to handle the `invoice.payment_succeeded` webhook, you should add a `handle_invoice_payment_succeeded` method to the controller:

```ruby
class WebhookController < Reji::WebhookController
  def handle_invoice_payment_succeeded(payload)
    # Handle The Event
  end
end
```

Next, define a route to your Reji controller within your `config/routes.rb` file. This will overwrite the default shipped route:

```ruby
post 'stripe/webhook', to: 'webhook#handle_webhook', as: 'webhook
```

<a name="handling-failed-subscriptions"></a>
### Failed Subscriptions

What if a customer's credit card expires? No worries - Reji's Webhook controller will cancel the customer's subscription for you. Failed payments will automatically be captured and handled by the controller. The controller will cancel the customer's subscription when Stripe determines the subscription has failed (normally after three failed payment attempts).

<a name="verifying-webhook-signatures"></a>
### Verifying Webhook Signatures

To secure your webhooks, you may use [Stripe's webhook signatures](https://stripe.com/docs/webhooks/signatures). For convenience, Reji automatically includes a middleware which validates that the incoming Stripe webhook request is valid.

To enable webhook verification, ensure that the `STRIPE_WEBHOOK_SECRET` environment variable is set. The webhook `secret` may be retrieved from your Stripe account dashboard.

<a name="single-charges"></a>
## Single Charges

<a name="simple-charge"></a>
### Simple Charge

> The `charge` method accepts the amount you would like to charge in the **lowest denominator of the currency used by your application**.

If you would like to make a "one off" charge against a subscribed customer's payment method, you may use the `charge` method on a billable model instance. You'll need to [provide a payment method identifier](#storing-payment-methods) as the second argument:

```ruby
# Stripe Accepts Charges In Cents...
stripe_charge = user.charge(100, payment_method)
```

The `charge` method accepts an array as its third argument, allowing you to pass any options you wish to the underlying Stripe charge creation. Consult the Stripe documentation regarding the options available to you when creating charges:

```ruby
user.charge(100, payment_method, {:custom_option => value})
```

You may also use the `charge` method without an underlying customer or user:

```ruby
stripe_charge = User.new.charge(100, payment_method)
```

The `charge` method will throw an exception if the charge fails. If the charge is successful, an instance of `Reji::Payment` will be returned from the method:

```ruby
begin
  payment = user.charge(100, payment_method)
rescue => e
  #
end
```

<a name="charge-with-invoice"></a>
### Charge With Invoice

Sometimes you may need to make a one-time charge but also generate an invoice for the charge so that you may offer a PDF receipt to your customer. The `invoice_for` method lets you do just that. For example, let's invoice the customer $5.00 for a "One Time Fee":

```ruby
# Stripe Accepts Charges In Cents...
user.invoice_for('One Time Fee', 500)
```

The invoice will be charged immediately against the user's default payment method. The `invoice_for` method also accepts an array as its third argument. This array contains the billing options for the invoice item. The fourth argument accepted by the method is also an array. This final argument accepts the billing options for the invoice itself:

```ruby
user.invoice_for('Stickers', 500, {
  :quantity => 50,
}, {
  :default_tax_rates => ['tax-rate-id'],
})
```

> The `invoice_for` method will create a Stripe invoice which will retry failed billing attempts. If you do not want invoices to retry failed charges, you will need to close them using the Stripe API after the first failed charge.

<a name="refunding-charges"></a>
### Refunding Charges

If you need to refund a Stripe charge, you may use the `refund` method. This method accepts the Stripe Payment Intent ID as its first argument:

```ruby
payment = user.charge(100, payment_method)
user.refund(payment.id)
```

<a name="invoices"></a>
## Invoices

<a name="retrieving-invoices"></a>
### Retrieving Invoices

You may easily retrieve an array of a billable model's invoices using the `invoices` method:

```ruby
invoices = user.invoices

# Include pending invoices in the results...
invoices = user.invoices_including_pending
```

You may use the `find_invoice` method to retrieve a specific invoice:

```ruby
invoice = user.find_invoice(invoice_id)
```

#### Displaying Invoice Information

When listing the invoices for the customer, you may use the invoice's helper methods to display the relevant invoice information. For example, you may wish to list every invoice in a table, allowing the user to easily download any of them:

```html
<table>
  <% invoices.each do |invoice| %>
    <tr>
      <td><%= invoice.date %></td>
      <td><%= invoice.total %></td>
      <td><a href="/user/invoice/<%= invoice.id %>">Download</a></td>
    </tr>
  <% end %>
</table>
```

<a name="generating-invoice-pdfs"></a>
### Generating Invoice PDFs

From within a controller, use the `download_invoice` method to generate a PDF download data of the invoice:

```ruby
class InvoicesController < ApplicationController
  before_action :authenticate_user!

  def download
    response = current_user.download_invoice(params[:id], {
      :vendor => 'Your Company',
      :product => 'Your Product',
    })

    send_data response[:data],
      :disposition => "inline; filename=#{response[:filename]}.pdf",
      :type => 'application/pdf'
  end
end
```

The `download_invoice` method also allows for an optional custom filename as the third parameter. This filename will automatically be suffixed with `.pdf` for you:

```ruby
response = current_user.download_invoice(params[:id], {
  :vendor => 'Your Company',
  :product => 'Your Product',
}, 'my-invoice')
```

<a name="handling-failed-payments"></a>
## Handling Failed Payments

Sometimes, payments for subscriptions or single charges can fail. When this happens, Reji will throw an `IncompletePaymentError` exception that informs you that this happened. After catching this exception, you have two options on how to proceed.

First, you could redirect your customer to the dedicated payment confirmation page which is included with Reji. This page already has an associated route that is registered via Reji's service provider. So, you may catch the `IncompletePaymentError` exception and redirect to the payment confirmation page:

```ruby
begin
  subscription = user.new_subscription('default', plan_id).create(payment_method)
rescue Reji::IncompletePaymentError => e
  redirect_to "/stripe/payment/#{e.payment.id}?redirect=/"
end
```

On the payment confirmation page, the customer will be prompted to enter their credit card info again and perform any additional actions required by Stripe, such as "3D Secure" confirmation. After confirming their payment, the user will be redirected to the URL provided by the `redirect` parameter specified above. Upon redirection, `message` (string) and `success` (integer) query string variables will be added to the URL.

Alternatively, you could allow Stripe to handle the payment confirmation for you. In this case, instead of redirecting to the payment confirmation page, you may [setup Stripe's automatic billing emails](https://dashboard.stripe.com/account/billing/automatic) in your Stripe dashboard. However, if a `IncompletePaymentError` exception is caught, you should still inform the user they will receive an email with further payment confirmation instructions.

Payment exceptions may be thrown for the following methods: `charge`, `invoice_for`, and `invoice` on the `Billable` user. When handling subscriptions, the `create` method on the `SubscriptionBuilder`, and the `increment_and_invoice` and `swap_and_invoice` methods on the `Subscription` model may throw exceptions.

There are currently two types of payment exceptions which extend `IncompletePaymentError`. You can catch these separately if needed so that you can customize the user experience:

<div class="content-list" markdown="1">
- `PaymentActionRequiredError`: this indicates that Stripe requires extra verification in order to confirm and process a payment.
- `PaymentFailureError`: this indicates that a payment failed for various other reasons, such as being out of available funds.
</div>

#### Incomplete and Past Due State

When a payment needs additional confirmation, the subscription will remain in an `incomplete` or `past_due` state as indicated by its `stripe_status` database column. Reji will automatically activate the customer's subscription via a webhook as soon as payment confirmation is complete.

For more information on `incomplete` and `past_due` states, please refer to [our additional documentation](#incomplete-and-past-due-status).

<a name="stripe-sdk"></a>
## Stripe SDK

Many of Reji's objects are wrappers around Stripe SDK objects. If you would like to interact with the Stripe objects directly, you may conveniently retrieve them using the `as_stripe` method:

```ruby
stripe_subscription = subscription.as_stripe_subscription
stripe_subscription.application_fee_percent = 5
stripe_subscription.save
```

You may also use the `update_stripe_subscription` method to update the Stripe subscription directly:

```ruby
subscription.update_stripe_subscription({:application_fee_percent => 5})
```

<a name="testing"></a>
## Testing

When testing an application that uses Reji, you may mock the actual HTTP requests to the Stripe API; however, this requires you to partially re-implement Reji's own behavior. Therefore, we recommend allowing your tests to hit the actual Stripe API. While this is slower, it provides more confidence that your application is working as expected and any slow tests may be placed within their own testing group. You also should only focus on testing the subscription and payment flow of your own application and not every underlying Reji behavior

You will need to set the Stripe testing secret environment variable in order to run the Reji tests.

```bash
STRIPE_SECRET=sk_test_<your-key> rake spec
```

Whenever you interact with Reji while testing, it will send actual API requests to your Stripe testing environment. For convenience, you should pre-fill your Stripe testing account with subscriptions / plans that you may then use during testing.

> In order to test a variety of billing scenarios, such as credit card denials and failures, you may use the vast range of [testing card numbers and tokens](https://stripe.com/docs/testing) provided by Stripe.

<a name="license"></a>
## License

Reji is open-sourced software licensed under the MIT license.
