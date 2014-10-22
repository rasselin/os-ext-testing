#! /usr/bin/env bash

# Sets up a master Jenkins server and associated machinery like
# Zuul, JJB, Gearman, etc.

set -e

THIS_DIR=`pwd`

DATA_REPO_INFO_FILE=$THIS_DIR/.data_repo_info
DATA_PATH=$THIS_DIR/os-ext-testing-data
OSEXT_PATH=$THIS_DIR/os-ext-testing
OSEXT_REPO=https://github.com/rasselin/os-ext-testing
PUPPET_MODULE_PATH="--modulepath=$OSEXT_PATH/puppet/modules:/root/system-config/modules:/etc/puppet/modules"

if ! sudo test -d /root/system-config; then
  sudo git clone https://review.openstack.org/p/openstack-infra/system-config.git \
    /root/system-config
fi

if ! sudo test -d /root/project-config; then
  sudo git clone https://github.com/openstack-infra/project-config.git \
    /root/project-config
fi

# Install Puppet and the OpenStack Infra Config source tree
# TODO(Ramy) Make sure sudo has http proxy settings...
if [[ ! -e install_puppet.sh ]]; then
  wget https://git.openstack.org/cgit/openstack-infra/system-config/plain/install_puppet.sh
  sudo bash -xe install_puppet.sh
  sudo /bin/bash /root/system-config/install_modules.sh
fi

# Update /root/system-config
echo "Update system-config"
sudo git  --work-tree=/root/system-config/ --git-dir=/root/system-config/.git remote update
sudo git  --work-tree=/root/system-config/ --git-dir=/root/system-config/.git pull

echo "Update project-config"
sudo git  --work-tree=/root/project-config/ --git-dir=/root/project-config/.git remote update
sudo git  --work-tree=/root/project-config/ --git-dir=/root/project-config/.git pull

# Clone or pull the the os-ext-testing repository
if [[ ! -d $OSEXT_PATH ]]; then
    echo "Cloning os-ext-testing repo..."
    git clone $OSEXT_REPO $OSEXT_PATH
fi

if [[ "$PULL_LATEST_OSEXT_REPO" == "1" ]]; then
    echo "Pulling latest os-ext-testing repo master..."
    cd $OSEXT_PATH; git checkout master && sudo git pull; cd $THIS_DIR
fi

if [[ ! -e $DATA_PATH ]]; then
    echo "Enter the URI for the location of your config data repository. Example: https://github.com/rasselin/os-ext-testing-data"
    read data_repo_uri
    if [[ "$data_repo_uri" == "" ]]; then
        echo "Data repository is required to proceed. Exiting."
        exit 1
    fi
    git clone $data_repo_uri $DATA_PATH
fi

if [[ "$PULL_LATEST_DATA_REPO" == "1" ]]; then
    echo "Pulling latest data repo master."
    cd $DATA_PATH; git checkout master && git pull; cd $THIS_DIR;
fi

# Pulling in variables from data repository
. $DATA_PATH/vars.sh

# Validate that the upstream gerrit user and key are present in the data
# repository
if [[ -z $UPSTREAM_GERRIT_USER ]]; then
    echo "Expected to find UPSTREAM_GERRIT_USER in $DATA_PATH/vars.sh. Please correct. Exiting."
    exit 1
else
    echo "Using upstream Gerrit user: $UPSTREAM_GERRIT_USER"
fi

if [[ ! -e "$DATA_PATH/$UPSTREAM_GERRIT_SSH_KEY_PATH" ]]; then
    echo "Expected to find $UPSTREAM_GERRIT_SSH_KEY_PATH in $DATA_PATH. Please correct. Exiting."
    exit 1
fi
export UPSTREAM_GERRIT_SSH_PRIVATE_KEY_CONTENTS=`cat "$DATA_PATH/$UPSTREAM_GERRIT_SSH_KEY_PATH"`

# Validate there is a Jenkins SSH key pair in the data repository
if [[ -z $JENKINS_SSH_KEY_PATH ]]; then
    echo "Expected to find JENKINS_SSH_KEY_PATH in $DATA_PATH/vars.sh. Please correct. Exiting."
    exit 1
elif [[ ! -e "$DATA_PATH/$JENKINS_SSH_KEY_PATH" ]]; then
    echo "Expected to find Jenkins SSH key pair at $DATA_PATH/$JENKINS_SSH_KEY_PATH, but wasn't found. Please correct. Exiting."
    exit 1
else
    echo "Using Jenkins SSH key path: $DATA_PATH/$JENKINS_SSH_KEY_PATH"
    JENKINS_SSH_PRIVATE_KEY_CONTENTS=`sudo cat $DATA_PATH/$JENKINS_SSH_KEY_PATH`
    JENKINS_SSH_PUBLIC_KEY_CONTENTS=`sudo cat $DATA_PATH/$JENKINS_SSH_KEY_PATH.pub`
fi

# Copy over the nodepool template
if [[ ! -e "$DATA_PATH/etc/nodepool/nodepool.yaml.erb" ]]; then
    echo "Expected to find nodepool template at $DATA_PATH/etc/nodepool/nodepool.yaml.erb, but wasn't found. Please create this using the sample provided. Exiting."
    exit 1
else
    cp -f $DATA_PATH/etc/nodepool/nodepool.yaml.erb $OSEXT_PATH/puppet/modules/os_ext_testing/templates/nodepool
fi

PUBLISH_HOST=${PUBLISH_HOST:-localhost}

# Create a self-signed SSL certificate for use in Apache
APACHE_SSL_ROOT_DIR=$THIS_DIR/tmp/apache/ssl
if [[ ! -e $APACHE_SSL_ROOT_DIR/new.ssl.csr ]]; then
    echo "Creating self-signed SSL certificate for Apache"
    mkdir -p $APACHE_SSL_ROOT_DIR
    cd $APACHE_SSL_ROOT_DIR
    echo '
[ req ]
default_bits            = 2048
default_keyfile         = new.key.pem
default_md              = default
prompt                  = no
distinguished_name      = distinguished_name

[ distinguished_name ]
countryName             = US
stateOrProvinceName     = CA
localityName            = Sunnyvale
organizationName        = OpenStack
organizationalUnitName  = OpenStack
commonName              = localhost
emailAddress            = openstack@openstack.org
' > ssl_req.conf
    # Create the certificate signing request
    openssl req -new -config ssl_req.conf -nodes > new.ssl.csr
    # Generate the certificate from the CSR
    openssl rsa -in new.key.pem -out new.cert.key
    openssl x509 -in new.ssl.csr -out new.cert.cert -req -signkey new.cert.key -days 3650
    cd $THIS_DIR
fi
APACHE_SSL_CERT_FILE=`cat $APACHE_SSL_ROOT_DIR/new.cert.cert`
APACHE_SSL_KEY_FILE=`cat $APACHE_SSL_ROOT_DIR/new.cert.key`

if [[ -z $UPSTREAM_GERRIT_SERVER ]]; then
    UPSTREAM_GERRIT_SERVER="review.openstack.org"
fi

CLASS_ARGS="jenkins_ssh_public_key => '$JENKINS_SSH_PUBLIC_KEY_CONTENTS', jenkins_ssh_private_key => '$JENKINS_SSH_PRIVATE_KEY_CONTENTS', "
CLASS_ARGS="$CLASS_ARGS ssl_cert_file_contents => '$APACHE_SSL_CERT_FILE', ssl_key_file_contents => '$APACHE_SSL_KEY_FILE', "
CLASS_ARGS="$CLASS_ARGS upstream_gerrit_server => '$UPSTREAM_GERRIT_SERVER', "
CLASS_ARGS="$CLASS_ARGS upstream_gerrit_user => '$UPSTREAM_GERRIT_USER', "
CLASS_ARGS="$CLASS_ARGS upstream_gerrit_ssh_private_key => '$UPSTREAM_GERRIT_SSH_PRIVATE_KEY_CONTENTS', "
CLASS_ARGS="$CLASS_ARGS upstream_gerrit_ssh_host_key => '$UPSTREAM_GERRIT_SSH_HOST_KEY', "
if [[ -n $UPSTREAM_GERRIT_BASEURL ]]; then
    CLASS_ARGS="$CLASS_ARGS upstream_gerrit_baseurl => '$UPSTREAM_GERRIT_BASEURL', "
fi
CLASS_ARGS="$CLASS_ARGS git_email => '$GIT_EMAIL', git_name => '$GIT_NAME', "
CLASS_ARGS="$CLASS_ARGS publish_host => '$PUBLISH_HOST', "
CLASS_ARGS="$CLASS_ARGS data_repo_dir => '$DATA_PATH', "
if [[ -n $URL_PATTERN ]]; then
    CLASS_ARGS="$CLASS_ARGS url_pattern => '$URL_PATTERN', "
fi

CLASS_ARGS="$CLASS_ARGS mysql_root_password => '$MYSQL_ROOT_PASSWORD', "
CLASS_ARGS="$CLASS_ARGS mysql_password => '$MYSQL_PASSWORD', "

CLASS_ARGS="$CLASS_ARGS provider_username => '$PROVIDER_USERNAME', "
CLASS_ARGS="$CLASS_ARGS provider_password => '$PROVIDER_PASSWORD', "
CLASS_ARGS="$CLASS_ARGS provider_image_name => '$PROVIDER_IMAGE_NAME', "
if [[ -n $PROVIDER_IMAGE_SETUP_SCRIPT_NAME ]]; then
    CLASS_ARGS="$CLASS_ARGS provider_image_setup_script_name => '$PROVIDER_IMAGE_SETUP_SCRIPT_NAME', "
fi

CLASS_ARGS="$CLASS_ARGS jenkins_api_user => '$JENKINS_API_USER', "
CLASS_ARGS="$CLASS_ARGS jenkins_api_key => '$JENKINS_API_KEY', "
CLASS_ARGS="$CLASS_ARGS jenkins_credentials_id => '$JENKINS_CREDENTIALS_ID', "
CLASS_ARGS="$CLASS_ARGS jenkins_ssh_public_key_no_whitespace => '$JENKINS_SSH_PUBLIC_KEY_NO_WHITESPACE', "


CLASS_ARGS="$CLASS_ARGS http_proxy => '$HTTP_PROXY', "
CLASS_ARGS="$CLASS_ARGS https_proxy => '$HTTPS_PROXY', "
CLASS_ARGS="$CLASS_ARGS no_proxy => '$NO_PROXY', "

sudo puppet apply --verbose $PUPPET_MODULE_PATH -e "class {'os_ext_testing::master': $CLASS_ARGS }"

#Not sure why nodepool private key is not getting set in the puppet scripts
sudo cp  $DATA_PATH/$JENKINS_SSH_KEY_PATH /home/nodepool/.ssh/id_rsa
