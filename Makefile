PROJECT = rabbitmq_1c
PROJECT_DESCRIPTION = RabbitMQ plugin for 1C
FORCE_PROJECT_VERSION = {vsn, "0.0.1"}
PROJECT_MOD = rabbit_1c_app
APP_VERSION = "1.0.0"

define PROJECT_ENV
[
 {webshovels, [
	      {test, [
		      {source, "amqp:///%2f"},
		      {destination, "https://www.corezoid.com/api/1/json/public/510759/e39aef64d16c7768f2ec97d850360ea742e5eb0e"},
		      {queue, <<"test">>}
		     ]}	
	     ]}
]
endef

define PROJECT_APP_EXTRA_KEYS
		{broker_version_requirements, []}
endef

DEPS = rabbit_common rabbit amqp_client rabbitmq_web_dispatch rabbitmq_management
TEST_DEPS = rabbitmq_ct_helpers rabbitmq_ct_client_helpers rabbitmq_amqp1_0
LOCAL_DEPS += mnesia ranch ssl crypto public_key

# FIXME: Add Ranch as a BUILD_DEPS to be sure the correct version is picked.
# See rabbitmq-components.mk.
BUILD_DEPS += ranch

DEP_EARLY_PLUGINS = rabbit_common/mk/rabbitmq-early-plugin.mk
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk cowboy

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk
