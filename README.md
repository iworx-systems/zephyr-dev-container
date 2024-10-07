# zephyr-dev-container
This container provides an environment to build embedded apps using [Zephyr](https://github.com/zephyrproject-rtos/zephyr).

## Environment Variables
The following environment variables need to be defined for the development container to function as intended:
 - PRJ_ROOT_DIR
 - APP_DIR
 - ZEPHYR_BASE

These are optional:
 - APP_CODECHECKER_CONFIG_FILE
 - TEST_DIR
 - NET_TOOLS_BASE

### Setting Environment Variables with vscode
The following is an example of the required environment variables being set by in a "devcontainer.json".

```
{
  "remoteEnv": {
    "PRJ_ROOT_DIR": "/workspaces/Turbine-Spirometer",
    "TEST_DIR": "${PRJ_ROOT_DIR}/app_tests",
    "APP_DIR": "${PRJ_ROOT_DIR}/app",
    "ZEPHYR_BASE": "${PRJ_ROOT_DIR}/zephyr_project/zephyr",
    "NET_TOOLS_BASE": "${PRJ_ROOT_DIR}/zephyr_project/tools/net-tools",
    "APP_CODECHECKER_CONFIG_FILE": "${PRJ_ROOT_DIR}/app/codechecker.json"
  }
}
```
