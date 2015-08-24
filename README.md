# OpenAperture.Overseer

[![Build Status](https://semaphoreci.com/api/v1/projects/c3d35030-ce62-4a5b-a757-65074469246f/403162/badge.svg)](https://semaphoreci.com/perceptive/overseer)

The Overseer module provides a standardized mechanism to manage and monitor OpenAperture system modules running in various MessagingExchanges.

## Contributing

To contribute to OpenAperture development, view our [contributing guide](http://openaperture.io/dev_resources/contributing.html)

## Module Responsibilities

The WorkflowOrchestrator module is responsible for the following actions within OpenAperture:

* Opening an AMQP channel to each module currently running in a MessagingExchange
* Send status updates to the OpenAperture Manager
* Update the OpenAperture Manager if a worker goes offline or becomes inactive
	* An inactive worker is defined as a worker that has not sent a status update in at least 10 minutes
	* An offline worker is defined as a worker that has not sent a status update in at least 20 minutes

## Messaging / Communication

The Overseer currently does not process any incoming messages.

## Module Configuration

The following configuration values must be defined either as environment variables or as part of the environment configuration files:

* Current Exchange
	* Type:  String
	* Description:  The identifier of the exchange in which the Orchestrator is running
  * Environment Variable:  EXCHANGE_ID
* Current Broker
	* Type:  String
	* Description:  The identifier of the broker to which the Orchestrator is connecting
  * Environment Variable:  BROKER_ID
* Manager URL
  * Type: String
  * Description: The url of the OpenAperture Manager
  * Environment Variable:  MANAGER_URL
  * Environment Configuration (.exs): :openaperture_manager_api, :manager_url
* OAuth Login URL
  * Type: String
  * Description: The login url of the OAuth2 server
  * Environment Variable:  OAUTH_LOGIN_URL
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_login_url
* OAuth Client ID
  * Type: String
  * Description: The OAuth2 client id to be used for authenticating with the OpenAperture Manager
  * Environment Variable:  OAUTH_CLIENT_ID
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_client_id
* OAuth Client Secret
  * Type: String
  * Description: The OAuth2 client secret to be used for authenticating with the OpenAperture Manager
  * Environment Variable:  OAUTH_CLIENT_SECRET
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_client_secret
* System Module Type
	* Type:  atom or string
	* Description:  An atom or string describing what kind of system module is running (i.e. builder, deployer, etc...)
  * Environment Configuration (.exs): :openaperture_overseer_api, :module_type

## Building & Testing

### Building

The normal elixir project setup steps are required:

```iex
mix do deps.get, deps.compile
```

To startup the application, use mix run:

```iex
MIX_ENV=prod elixir --sname workflow_orchestrator -S mix run --no-halt
```

### Testing 

You can then run the tests

```iex
MIX_ENV=test mix test test/
```
