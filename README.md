# Quick start with Wallarm using the Shell script

This repository contains the Shell script that automates the Wallarm NGINX-based node deployment steps. The script has to be run on a server with one of the following supported Linux‑based operating system (OS):

* Debian 11.x (bullseye)
* Ubuntu 18.04 LTS (bionic)
* Ubuntu 20.04 LTS (focal)
* Ubuntu 22.04 LTS (jammy)
* CentOS 7.x
* AlmaLinux
* Rocky Linux
* Oracle Linux 8.x

This approach is recommended to be used only to try the product, it is not recommended for productions environments.

## How the quick start script works

The Shell script **getwallarm.sh** used for Wallarm quick start performs the following steps:

1. Disable the [SELinux](https://www.redhat.com/en/topics/linux/what-is-selinux) mechanism if it is installed on the OS. Wallarm quick deployment is not compatible with active SELinux.
1. Install the latest stable version of NGINX from the NGINX official repository.
1. Install the Wallarm packages for both the Wallarm NGINX and postanalytics modules.
1. Run the filtering node using its token in the **blocking** [mode](https://docs.wallarm.com/admin-en/configure-wallarm-mode).
1. Configure the local NGINX instance to act as a [reverse proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) for the specified domain.
1. Send the following test requests:

    * GET request to `http://127.0.0.8/wallarm-status` to check the accessibility of the [Wallarm statistics service](https://docs.wallarm.com/admin-en/configure-statistics-service).
    * GET request to the NGINX instance address (port 80/TCP) to check the accessibility of the domain protected by Wallarm.
    * GET request containing malicious payload of the [Path Traversal](https://docs.wallarm.ru/attacks-vulns-list/#path-traversal) type to the NGINX instance address:

        ```
        curl -H "Host: $DOMAIN_NAME" http://localhost/etc/passwd
        ```

        The request should be blocked by the Wallarm node (the HTTP response code should be 403).

    If the actual response is different from the expected one, the script returns the corresponding message.

## Quickstart procedure

1. Create an account in Wallarm Console using the link either for the [US](https://us1.my.wallarm.com/signup) or [EU](https://my.wallarm.com/signup) Wallarm Cloud.

    [More details on Wallarm Clouds →](https://docs.wallarm.com/about-wallarm-waf/overview#cloud)
1. Create the Wallarm node in the **Nodes** section of the Wallarm Console UI.
1. Copy the generated token.
1. Install one of the supported OS listed below on your server. For the Wallarm node deployment to be completed successfully, please install the OS from the image/distributive with the basic package set and do not apply any additional configurations to the installed OS. The quick start script may not be able to handle the OS customizations (e.g. security hardening or additional configurations fitting your internal server management standards).

    * Debian 11.x (bullseye)
    * Ubuntu 18.04 LTS (bionic)
    * Ubuntu 20.04 LTS (focal)
    * Ubuntu 22.04 LTS (jammy)
    * CentOS 7.x
    * AlmaLinux
    * Rocky Linux
    * Oracle Linux 8.x
1. Connect to the server and become root user (e.g. by using command `sudo -i`).
1. Download the script **getwallarm.sh** by using one of the following commands:

    If the curl command is available:
    
    ```
    curl -o getwallarm.sh https://raw.githubusercontent.com/wallarm/quick-start/stable/4.4/getwallarm.sh
    ```
    
    If the wget command is available:
    
    ```
    wget -O getwallarm.sh https://raw.githubusercontent.com/wallarm/quick-start/stable/4.4/getwallarm.sh
    ```
1. Run the script passing the proper parameters:

    ```bash
    sh getwallarm.sh -t <DEPLOY_TOKEN> -S <WALLARM_CLOUD> -n <WALLARM_NODE_NAME> -d <DOMAIN_NAME> -o <ORIGIN_SERVER>
    ```

    | Parameter | Description | Required? |
    | --------- | ----------- | --------- |
    | `<DEPLOY_TOKEN>` | Wallarm node token copied from the Wallarm Console UI. | Yes	
    | `<WALLARM_CLOUD>` | Wallarm Cloud name being used. Possible values are `eu` (by default) and `us1`. | No
    | `<WALLARM_NODE_NAME>` | Wallarm node name. By default, the script assigns the host name to the node.<br><br>The specified name can be changed in Wallarm Console → **Nodes** later. | No
    | `<DOMAIN_NAME>` | The Wallarm filtering node will be configured to handle traffic for this domain. The value can be your company website or public API endpoint. If not sure about which domain name to use, you can always experiment with any public site (e.g. `example.com`).<br><br>Default value is `localhost`. | No
    | `<ORIGIN_SERVER>` | The Wallarm filtering node will be configured to send upstream requests to the specified IP address or domain name. If this parameter is not specified explicitly, the script uses the value of `<DOMAIN_NAME>`. | No
1. Ensure the script returned the message `We've completed the Wallarm node deployment process`.

    If any errors occurred during the script execution, the script would return appropriate error messages.
1. Open Wallarm Console → **Events** section in the [US Cloud](https://us1.my.wallarm.com/search) or [EU Cloud](https://my.wallarm.com/search) and make sure the Path Traversal attack is displayed in the list.

## Next steps

Wallarm node quick deployment is successfully completed!

To continue the product exploring, we recommend learning more about the following Wallarm features:

* [Configuration of traffic filtration mode](https://docs.wallarm.com/admin-en/configure-wallarm-mode)
* [Blocking page and error code configuration](https://docs.wallarm.com/admin-en/configuration-guides/configure-block-page-and-code)
* [Customizing the traffic filtration rules](https://docs.wallarm.com/user-guides/rules/intro)
* [IP address whitelisting, blacklisting and greylisting](https://docs.wallarm.com/user-guides/ip-lists/overview)
* System event notifications configured via [native integrations with DevOps tools](https://docs.wallarm.com/user-guides/settings/integrations/integrations-intro) and [triggers](https://docs.wallarm.com/user-guides/triggers/triggers)

## Wallarm node production deployment

When the Wallarm quick start is completed and basic features are explored, you are recommended to proceed to the production deployment.

[Wallarm production deployment options →](https://docs.wallarm.com/admin-en/supported-platforms)
