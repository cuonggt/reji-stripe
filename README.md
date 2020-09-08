# Rails Reji

- [Introduction](#introduction)
- [Installation](#installation)
- [Configuration](#configuration)
    - [Billable Model](#billable-model)
    - [API Keys](#api-keys)
    - [Currency Configuration](#currency-configuration)
- [Stripe SDK](#stripe-sdk)
- [Testing](#testing)
- [License](#license)

<a name="introduction"></a>
## Introduction

Reji provides an expressive, fluent interface to [Stripe's](https://stripe.com) subscription billing services for your Rails applications. It handles almost all of the boilerplate subscription billing code you are dreading writing. In addition to basic subscription management, Reji can handle coupons, swapping subscription, subscription "quantities", cancellation grace periods, and even generate invoice PDFs.

<a name="installation"></a>
## Installation

Reji is a Rails gem tested against Rails `>= 5.0` and Ruby `>= 2.4.0`.

You can add it to your Gemfile with:

```sh
gem 'reji'
```

Run the bundle command to install it.

After you install Reji, you need to run the generator:

```shell
rails generate reji:install
```

The Reji install generator:

* Creates an initializer file to allow further configuration.
* Creates migration files that add several columns to your `users` table as well as create a new `subscriptions` table to hold all of your customer's subscriptions.

> To prevent breaking changes, Reji uses a fixed Stripe API version. Reji currently utilizes Stripe API version `2020-08-27`. The Stripe API version will be updated on minor releases in order to make use of new Stripe features and improvements.

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

Next, you should configure your Stripe keys in your environment variables or `.env` file. You can retrieve your Stripe API keys from the Stripe control panel.

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

```shell
STRIPE_SECRET=sk_test_<your-key> rake spec
```

Whenever you interact with Reji while testing, it will send actual API requests to your Stripe testing environment. For convenience, you should pre-fill your Stripe testing account with subscriptions / plans that you may then use during testing.

> In order to test a variety of billing scenarios, such as credit card denials and failures, you may use the vast range of [testing card numbers and tokens](https://stripe.com/docs/testing) provided by Stripe.

<a name="license"></a>
## License

Reji is open-sourced software licensed under the MIT license.
