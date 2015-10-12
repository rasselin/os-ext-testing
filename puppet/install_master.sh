#! /usr/bin/env bash

# Sets up a master Jenkins server and associated machinery like
# Zuul, JJB, Gearman, etc.

set -e

THIS_DIR=`pwd`

DATA_REPO_INFO_FILE=$THIS_DIR/.data_repo_info
DATA_PATH=$THIS_DIR/os-ext-testing-data
OSEXT_PATH=$THIS_DIR/os-ext-testing
OSEXT_REPO=https://github.com/rasselin/os-ext-testing
OSEXT_BRANCH=master
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
# Puppet module splits requires re-installing modules from the new location
sudo /bin/bash /root/system-config/install_modules.sh

# Clone or pull the the os-ext-testing repository
if [[ ! -d $OSEXT_PATH ]]; then
    echo "Cloning os-ext-testing repo..."
    git clone -b $OSEXT_BRANCH $OSEXT_REPO $OSEXT_PATH
fi

if [[ "$PULL_LATEST_OSEXT_REPO" == "1" ]]; then
    echo "Pulling latest os-ext-testing repo master..."
    cd $OSEXT_PATH; git checkout $OSEXT_BRANCH && sudo git pull; cd $THIS_DIR
fi

if [[ ! -e $DATA_PATH ]]; then
    if [[ -z $PROJECT_CONFIG ]]; then
        echo "Enter the URI for the location of your project-config data repository. Example: https://github.com/rasselin/os-ext-testing-data"
        read data_repo_uri
        if [[ "$data_repo_uri" == "" ]]; then
            echo "Data repository is required to proceed. Exiting."
            exit 1
        fi
    else
        data_repo_uri=$PROJECT_CONFIG
    fi
    git clone $data_repo_uri $DATA_PATH
fi

if [[ "$PULL_LATEST_DATA_REPO" == "1" ]]; then
    echo "Pulling latest data repo master."
    cd $DATA_PATH; git checkout master && git pull; cd $THIS_DIR;
fi

# Pulling in variables from data repository
echo "Pulling in custom vars from $DATA_PATH/vars.sh"
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
    JENKINS_SSH_PUBLIC_KEY_NO_WHITESPACE=`sudo cat $DATA_PATH/$JENKINS_SSH_KEY_PATH.pub | cut -d' ' -f 2`
fi

PUBLISH_HOST=${PUBLISH_HOST:-localhost}

if [[ -z $UPSTREAM_GERRIT_SERVER ]]; then
    echo "No upstream gerrit server defined. Defaulting to review.openstack.org."
    UPSTREAM_GERRIT_SERVER="review.openstack.org"
fi

gerrit_args="upstream_gerrit_server => '$UPSTREAM_GERRIT_SERVER',
upstream_gerrit_user => '$UPSTREAM_GERRIT_USER',
upstream_gerrit_ssh_private_key => '$UPSTREAM_GERRIT_SSH_PRIVATE_KEY_CONTENTS',
upstream_gerrit_ssh_host_key => '$UPSTREAM_GERRIT_SSH_HOST_KEY',"

if [[ -n $UPSTREAM_GERRIT_BASEURL ]]; then
    gerrit_args+="upstream_gerrit_baseurl => '$UPSTREAM_GERRIT_BASEURL', "
fi

zuul_args="git_email => '$GIT_EMAIL',
git_name => '$GIT_NAME',
publish_host => '$PUBLISH_HOST',
data_repo_dir => '$DATA_PATH',"
if [[ -n $URL_PATTERN ]]; then
    zuul_args+="url_pattern => '$URL_PATTERN', "
fi
if [[ -n $SMTP_HOST ]]; then
    zuul_args+="smtp_host => '$SMTP_HOST', "
fi

if [[ -n $PROJECT_CONFIG ]]; then
    zuul_args+="project_config_repo => '$PROJECT_CONFIG', "
else
    zuul_args+="project_config_repo => '$OSEXT_REPO', "
    echo "This repo now requires the use of project-config. Using $OSEXT_REPO."
    echo "See https://github.com/rasselin/os-ext-testing-data#migrate-to-project-config for the instructions to migrate."
fi
if [[ -n $ZUUL_REPO ]]; then
    zuul_args+="zuul_git_source_repo => '$ZUUL_REPO', "
fi
if [[ -n $ZUUL_REVISION ]]; then
    zuul_args+="zuul_revision => '$ZUUL_REVISION', "
fi


nodepool_args="mysql_root_password => '$MYSQL_ROOT_PASSWORD',
               mysql_password => '$MYSQL_PASSWORD',"

if [[ -n $NODEPOOL_REPO ]]; then
    nodepool_args+="nodepool_git_source_repo => '$NODEPOOL_REPO', "
fi
if [[ -n $NODEPOOL_REVISION ]]; then
    nodepool_args+="nodepool_revision => '$NODEPOOL_REVISION', "
fi

if [[ -z $JENKINS_API_PASSWORD ]]; then
    JENKINS_API_PASSWORD=""
fi

jenkins_args="jenkins_ssh_public_key => '$JENKINS_SSH_PUBLIC_KEY_CONTENTS',
              jenkins_ssh_private_key => '$JENKINS_SSH_PRIVATE_KEY_CONTENTS',
              jenkins_api_user => '$JENKINS_API_USER',
              jenkins_api_password => '$JENKINS_API_PASSWORD',
              jenkins_api_key => '$JENKINS_API_KEY',
              jenkins_credentials_id => '$JENKINS_CREDENTIALS_ID',
              jenkins_ssh_public_key_no_whitespace => '$JENKINS_SSH_PUBLIC_KEY_NO_WHITESPACE',"

CLASS_ARGS="$gerrit_args $zuul_args $nodepool_args $jenkins_args"
sudo puppet apply --verbose $PUPPET_MODULE_PATH -e "class {'os_ext_testing::master': $CLASS_ARGS }"

