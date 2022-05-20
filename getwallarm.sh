#!/bin/sh
# 
# The script can be used to quickly deploy and configure a Wallarm node on a supported Linux OS.
#

# The name of the script - used for tagging of syslog messages
TAG="getwallarm.sh"

# Log a message to the console and syslog.
log_message() {
	SEVERITY=$1
	MESSAGE=$2
	echo "$(date):" "$SEVERITY" "$MESSAGE"
	logger -t "$TAG" "$SEVERITY" "$MESSAGE"
}

usage() {
	echo "Usage: 

	Supported parameters (all parameters are optional):
		-h
			This help message.
		-S <WALLARM_CLOUD>
			The name of Wallarm Cloud being used: eu, ru, us1 or custom (by default the script uses EU Cloud).
		-t <DEPLOY_TOKEN>
			The Wallarm node token copied from Wallarm Console.
		-n <NODE_MAME>
			The name of the node as it will be visible in Wallarm Console (by 
			default the script will use the host name).
		-d <DOMAIN_NAME>
			The Wallarm reverse proxy will be configured to handle traffic for this domain.
		-o <ORIGIN_SERVER>
			The Wallarm reverse proxy will be configured to send upstream requests to the
			specified IP address or domain name.
		-x
			Skip checking the DOMAIN NAME and the ORIGIN SERVER."
}

check_if_root() {
	log_message INFO "Checking whether the script is run as root..."
	if [ "$(id -u)" -ne 0 ]; then
		log_message ERROR "This script must be executed with root permissions" 
		exit 1
	fi
}


check_domain() {
	if [ -z "$SKIP_CHECK" ] && [ -n "$DOMAIN_NAME" ]; then
		log_message INFO "Checking '$DOMAIN_NAME' resolution..."
		ping -c1 "$DOMAIN_NAME"
		if [ "$?" -eq 2 ]; then
			log_message ERROR "Failed to resolve '$DOMAIN_NAME'. Please specify another domain name or use the '-x' option to skip this check." 
	  		exit 1
		fi
	fi
}

check_origin() {
	if [ -z "$SKIP_CHECK" ] && [ -n "$ORIGIN_NAME" ]; then
		log_message INFO "Checking connectivity to '$ORIGIN_NAME'..."
		if ! curl "$ORIGIN_NAME"; then
			log_message ERROR "Failed to check connectivity to '$ORIGIN_NAME'. Please specify another origin name or use the '-x' option to skip this check." 
	  		exit 1
		fi
	fi
}

disable_selinux() {
        log_message INFO "Checking whether SELinux is installed (and disabling it if it is installed)..."
	SELINUXENABLED=$(which selinuxenabled)
	SETENFORCE=$(which setenforce)
        if [ -z "$SELINUXENABLED" ]; then
                log_message INFO "Cannot find 'selinuxenabled' binary - it looks like SELinux is not installed on the server."
                return
        fi

        if [ -z "$SETENFORCE" ]; then
                log_message WARNING "Cannot find 'setenforce' tool - will not try to disable SELinux..."
                return
        fi

        log_message INFO "Running 'setenforce' command to temporary disable SELinux..."
        setenforce 0

        SELINUX_CONF=/etc/selinux/config
        if [ -f "$SELINUX_CONF" ]; then
                log_message INFO "Updating file $SELINUX_CONF to permanently disable SELinux..."
                if ! sed -i 's/enforcing/disabled/g' $SELINUX_CONF; then
			log_message CRTICAL "Failed to update file $SELINUX_CONF and disable SELinux - aborting"
			exit 1
		fi
		
        fi
}

get_distro() {
	log_message INFO "Discovering the used operating system..." 
	lsb_dist=""
	osrelease=""
	pretty_name=""
	basearch=""

	# Every system that we support has /etc/os-release or not?
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
		osrelease="$(. /etc/os-release && echo "$VERSION_ID")"
		if [ "$lsb_dist" = "centos" ]; then
		    if [ "$osrelease" = 7 ]; then
			pretty_name="centos"
			lsb_dist="$( rpm -qa \centos-release | cut -d"-" -f1 )"
			osrelease="$( rpm -qa \centos-release | cut -d"-" -f3 )"
			basearch=$(rpm -q --qf "%{arch}" -f /etc/$distro)
		    elif [ "$osrelease" = 8 ]; then
			pretty_name="centos"
			lsb_dist="$( rpm -qa \centos-linux-release | cut -d"-" -f1 )"
			# osrelease="$( rpm -qa \centos-release | cut -d"-" -f3 )"
			basearch=$(rpm -q --qf "%{arch}" -f /etc/$distro)
		    else
			log_message ERROR "It looks like Wallarm does not support your CentOS OS. Detected OS details: osrelease = \"$osrelease\""
			exit 1
		    fi
		elif [ "$osrelease" = 10 ]; then
			pretty_name="buster"
		elif [ "$osrelease" = 11 ]; then
			pretty_name="bullseye"
		elif [ "$osrelease" = 18.04 ]; then
			pretty_name="bionic"
		elif [ "$osrelease" = 20.04 ]; then
			pretty_name="focal"			
		else
			log_message ERROR "It looks like Wallarm does not support your OS. Detected OS details: osrelease = \"$osrelease\""
			exit 1
		fi
	elif [ -r /etc/centos-release ]; then
		lsb_dist="$( rpm -qa \centos-release | cut -d"-" -f1 )"
		osrelease="$( rpm -qa \centos-release | cut -d"-" -f3 )"
		basearch=$(rpm -q --qf "%{arch}" -f /etc/$distro)
	else
		log_message ERROR "It looks like Wallarm does not support your OS. Detected OS details: osrelease = \"$osrelease\""
		exit 1
	fi 

	log_message INFO "Detected OS details: lsb_dist=$lsb_dist, osrelease=$osrelease, pretty_name=$pretty_name, basearch=$basearch"
}

#install 
do_install() {

	#do some platform detection
	get_distro

	#install nginx    

	case $lsb_dist in
		debian|ubuntu)
			log_message INFO "Configuring official NGINX repository key..."
			apt-get update && apt-get install wget apt-transport-https dirmngr -y
			KEY_FILE=nginx_signing.key
			wget -O "$KEY_FILE" "https://nginx.org/keys/$KEY_FILE"
			if [ ! -s "$KEY_FILE" ]; then
				log_message CRITICAL "Failed to download the file $KEY_FILE - aborting..."
				exit 1
			fi
			if ! apt-key add "$KEY_FILE"; then
				log_message CRITICAL "apt-key failed to add the file $KEY_FILE - aborting..."
				exit 1
			fi

			log_message INFO "Configuring official NGINX repository..."
			sh -c "echo 'deb https://nginx.org/packages/$lsb_dist/ $pretty_name nginx'\
				> /etc/apt/sources.list.d/nginx.list"
			sh -c "echo 'deb-src https://nginx.org/packages/$lsb_dist/ $pretty_name nginx'\
				>> /etc/apt/sources.list.d/nginx.list"

			log_message INFO "Removing nginx-common package..." 
			apt-get remove nginx-common

			log_message INFO "Installing official NGINX package..."
			apt-get update
			if ! apt-get install -y nginx; then
				log_message CRITICAL "Failed to install package nginx - aborting"
				exit 1
			fi

			log_message INFO "Adding Wallarm repository key..."
			curl -fsSL https://repo.wallarm.com/wallarm.gpg | sudo apt-key add -
			
			log_message INFO "Configuring Wallarm repository..."
			sh -c "echo 'deb http://repo.wallarm.com/$lsb_dist/wallarm-node\
				$pretty_name/4.0/'\
				>/etc/apt/sources.list.d/wallarm.list"
			apt-get update

			log_message INFO "Installing Wallarm packages..."
			if ! apt-get install -y --no-install-recommends wallarm-node nginx-module-wallarm; then
				log_message CRITICAL "Failed to install Wallarm node packages - aborting."
				exit 1
			fi

			;;
		centos)
			log_message INFO "Configuring official NGINX repository..."
			echo "[nginx]" > /etc/yum.repos.d/nginx.repo
			echo "name=nginx repo" >> /etc/yum.repos.d/nginx.repo
			echo "baseurl=https://nginx.org/packages/centos/$osrelease/$basearch/" >> /etc/yum.repos.d/nginx.repo
			echo "gpgcheck=0" >> /etc/yum.repos.d/nginx.repo
			echo "enabled=1" >> /etc/yum.repos.d/nginx.repo
			echo "gpgkey=https://nginx.org/keys/nginx_signing.key" >> /etc/yum.repos.d/nginx.repo
			echo "module_hotfixes=true" >> /etc/yum.repos.d/nginx.repo
			case $osrelease in
				7)
					if rpm --quiet -q epel-release; then
						if ! rpm --quiet -q yum-utils; then
							yum install -y yum-utils
						fi
						yum-config-manager --save --setopt=epel.exclude=nginx\*;
					fi
					;;					
			esac

			log_message INFO "Installing official NGINX packages..."
			yum update -y
			if ! rpm --quiet -q nginx; then
				if ! yum install nginx -y; then
					log_message CRITICAL "Failed to install package nginx - aborting."
					exit 1
				fi
			fi

			log_message INFO "Configuring Wallarm repository..."
			case $osrelease in
				7)
					if ! rpm --quiet -q epel-release; then
						yum install -y epel-release
					fi
					if ! rpm --quiet -q yum-utils; then
						yum install -y yum-utils
					fi
					yum-config-manager  --save --setopt=epel.exclude=nginx\*;
					if ! rpm --quiet -q wallarm-node-repo; then
						rpm -i https://repo.wallarm.com/centos/wallarm-node/7/4.0/x86_64/Packages/wallarm-node-repo-1-6.el7.noarch.rpm
					fi
					;;
				8)
					if ! rpm --quiet -q epel-release; then
						yum install -y epel-release
					fi
					if ! rpm --quiet -q wallarm-node-repo; then
						rpm -i https://repo.wallarm.com/centos/wallarm-node/8/4.0/x86_64/Packages/wallarm-node-repo-1-6.el8.noarch.rpm
					fi
					;;					
			esac

			log_message INFO "Installing Wallarm packages..."
			yum update -y
			if ! rpm --quiet -q wallarm-node; then
				if ! yum install -y wallarm-node nginx-module-wallarm; then
					log_message CRITICAL "Failed to install Wallarm node packages - aborting."
					exit 1
				fi
			fi

			;;
	esac

	NGINX_CONF=/etc/nginx/nginx.conf
	log_message INFO "Checking whether $NGINX_CONF is already configured to load the Wallarm module..."

	if grep -q ngx_http_wallarm_module.so $NGINX_CONF; then
		log_message INFO "It looks like the file is already configured to load the module."
	else
		log_message INFO "Updating $NGINX_CONF to load Wallarm NGINX module..."
		sed -i '/worker_processes.*/a load_module modules/ngx_http_wallarm_module.so;' /etc/nginx/nginx.conf
	fi

	CONF_DIR=/etc/nginx/conf.d/
	if [ -f $CONF_DIR/wallarm.conf -o -f $CONF_DIR/wallarm-status.conf ]; then
		log_message INFO "It looks like default Wallarm configuration files already presented in the $CONF_DIR directory."
	else
		log_message INFO "Copying default Wallarm configuration files to $CONF_DIR directory..."
		cp /usr/share/doc/nginx-module-wallarm/examples/*.conf $CONF_DIR
	fi

	log_message INFO "Enabling NGINX to launch automatically during the server startup sequence..."
	systemctl enable nginx
}

# 
# Add the node the the cloud
#
add_node() {
	log_message INFO "Working on connecting the node to the Wallarm Cloud..."

	NODE_CONF=/etc/wallarm/node.yaml

	ADDNODE_SCRIPT=/usr/share/wallarm-common/register-node
	if [ ! -x $ADDNODE_SCRIPT ]; then
		log_message ERROR "Expected script $ADDNODE_SCRIPT is not presented - something is wrong with Wallarm packages - aborting."
       		exit 1
	fi

	log_message INFO "Running $ADDNODE_SCRIPT script to add the new node to the Wallarm Cloud (API endpoint $API_HOST)..."
	if ! $ADDNODE_SCRIPT --force -H "$API_HOST" -P "$API_PORT" "$API_SSL_ARG" --token "$API_TOKEN" --name "$MY_NODE_NAME"; then
		log_message CRITICAL "Failed to register the node in Wallarm Cloud - aborting..."
		exit 1
	fi
	if [ ! -s "$NODE_CONF" ]; then
		log_message CRITICAL "Node configuration $NODE_CONF is empty or does not exist - aborting."
		exit 1
	fi 
}

#
# Configure the NGINX to handle the specified domain in reverse proxy mode
#
configure_proxy() {
	log_message INFO "Checking whether we need to configure the NGINX proxy..."
	CONF_FILE=/etc/nginx/conf.d/wallarm-proxy.conf	

	if [ -z "$DOMAIN_NAME" ]; then
		log_message INFO "Script parameter -d is not specified - skipping the proxy configuration step..."
		return
	fi

	if [ -z "$ORIGIN_NAME" ]; then
		log_message INFO "Origin address is not specified (script option -o) - using domain name $DOMAIN_NAME"
		ORIGIN_NAME=$DOMAIN_NAME
	fi

	log_message INFO "Creating NGINX configuration file $CONF_FILE with settings for domain $DOMAIN_NAME and origin address $ORIGIN_NAME..."

cat > $CONF_FILE << EOF

# Set global Wallarm mode to "block"
wallarm_mode block;

server {

  listen       80;
  # the domains for which traffic is processed
  server_name $DOMAIN_NAME;

  # wallarm_mode monitoring; 
  # wallarm_instance 1;

  # Enable Libdetection
  wallarm_enable_libdetection on;
  proxy_request_buffering on;

  location / {
    # setting the address for request forwarding
    proxy_pass http://$ORIGIN_NAME;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}

EOF

	if [ -n "$WALLARM_STATUS_ALLOW" ]; then
		log_message INFO "Creating an external 'wallarm-status' location..."
		{
		printf "  location /wallarm-status {\n"
		for cidr in $(echo "$WALLARM_STATUS_ALLOW" | sed "s/,/ /g"); do
			printf "    allow %s;\n" "$cidr"
		done
		printf "    deny all;\n"
		printf "    wallarm_status on;\n"
		printf "    wallarm_mode off;\n"
		printf "  }\n\n"
		} >/tmp/wallarm-status.conf

		line_for_insert=$(grep -n "location / {" "$CONF_FILE" | cut -f 1 -d:)
		line_for_insert=$((line_for_insert - 1))
		sed -i "${line_for_insert}r /tmp/wallarm-status.conf" "$CONF_FILE"
	fi


	log_message INFO "Using 'nginx -t' command verifying that the NGINX configuration is correct..."
	if ! nginx -t; then
		log_message ERROR "It looks like NGINX doesn't like the new configuration - aborting."
		exit 1
	fi

        log_message INFO "Starting the NGINX service (just in case if it is not running)..."
        service nginx start

	log_message INFO "Reloading NGINX configuration..."
	service nginx reload

}

#
# Send a few test requests
#
test_proxy() {
	log_message INFO "Sending a request to Wallarm status page http://127.0.0.8/wallarm-status..."
	curl http://127.0.0.8/wallarm-status

	if [ -z "$DOMAIN_NAME" ]; then
		log_message INFO "The domain name is not specified - skipping the domain testing step..."
		return
	fi
	log_message INFO "Sending a regular HTTP request to the localhost for domain $DOMAIN_NAME..."
	curl -v -H "Host: $DOMAIN_NAME" http://localhost/ > /dev/null

	log_message INFO "Sending a malicious HTTP request to the localhost for domain $DOMAIN_NAME (the response code should be 403)..."
	curl -v -H "Host: $DOMAIN_NAME" "http://localhost/?id='or+1=1--a-<script>prompt(1)</script>" > /dev/null
}

# By default use the Wallarm EU Cloud
WALLARM_CLOUD=eu
API_PORT=444
API_SSL_ARG=""

MY_NODE_NAME=`hostname`

while getopts :ht:d:o:n:S:x option
do
	case "$option" in
		h)
			usage;
			exit 1
			;;
		t)
			# Wallarm token for the node registration
			API_TOKEN=$OPTARG;
			;;
		n)
			# The name of the node
			MY_NODE_NAME=$OPTARG;
			;;
		d)
			# Domain name as recognized by this node and the origin server
			DOMAIN_NAME=$OPTARG;
			;;
		o)
			# IP address or DNS name of the origin server
			ORIGIN_NAME=$OPTARG;
			;;
		S)	
			# Wallarm Cloud being used (eu, ru or us1)
			WALLARM_CLOUD=`echo $OPTARG | tr '[:upper:]' '[:lower:]'`;
			;;
		x)
			# Skip checking the DOMAIN NAME and the ORIGIN SERVER
			SKIP_CHECK=1;
			;;
		*)
			echo "Hmm, an invalid option was received."
			usage
			exit 1
			;;
	esac
done

if [ ! -z "$API_TOKEN" ]; then
	log_message ERROR "Please specify token (DEPLOY_TOKEN) parameter."
	usage
	exit 1
fi

if [ "$WALLARM_CLOUD" = "us1" ]; then
	API_HOST=us1.api.wallarm.com
elif [ "$WALLARM_CLOUD" = "eu" ]; then
	API_HOST=api.wallarm.com
elif [ "$WALLARM_CLOUD" = "ru" ]; then
	API_HOST=api.wallarm.ru
elif [ "$WALLARM_CLOUD" = "custom" ]; then
	if [ -z "$WALLARM_API_HOST" ]; then
		log_message ERROR "For a custom cloud, you must set the WALLARM_API_HOST environment variable"
		exit 1
	else
		API_HOST="$WALLARM_API_HOST"
	fi

	if [ -n "$WALLARM_API_PORT" ]; then
		API_PORT="$WALLARM_API_PORT"
	fi

	if [ "$WALLARM_API_USE_SSL" = "false" ]; then
		API_SSL_ARG="--no-ssl"
	fi
else
	log_message ERROR "Unknown Wallarm Cloud name \"$WALLARM_CLOUD\". Accepted Wallarm Cloud names are eu, ru or us1. Aborting."
	usage
	exit 1
fi

check_if_root

check_domain

check_origin

disable_selinux

do_install

add_node

configure_proxy

test_proxy

log_message INFO "We've completed the Wallarm node deployment process."