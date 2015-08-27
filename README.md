# OpenStack External Test Platform

!! THIS REPOSITORY IS VERY MUCH A WORK IN PROGRESS !!

PLEASE USE AT YOUR OWN RISK AND PROVIDE FEEDBACK IF YOU CAN!

This repository contains documentation and modules in a variety
of configuration management systems that demonstrates setting up
a real-world external testing platform that links with the upstream
OpenStack CI platform.

It installs Jenkins, Jenkins Job Builder (JJB), the Gerrit
Jenkins plugin, Nodepool, and a set of scripts that make
running a variety of OpenStack integration tests easy.

Currently only Puppet modules are complete and tested. 

Background reading:
[third_party](http://ci.openstack.org/third_party.html)

The links below contain some out of date information:

[understanding-the-openstack-ci-system](http://www.joinfu.com/2014/01/understanding-the-openstack-ci-system/)

[setting-up-an-external-openstack-testing-system/](http://www.joinfu.com/2014/02/setting-up-an-external-openstack-testing-system/)

[setting-up-an-openstack-external-testing-system-part-2](http://www.joinfu.com/2014/02/setting-up-an-openstack-external-testing-system-part-2/)


## NEW 7/1/2015: This repo is being migrated to use project-config and puppet-openstackci
This 3rd party ci repo is in the process of being migrated to use the
[common-ci approach] (http://specs.openstack.org/openstack-infra/infra-specs/specs/openstackci.html)

As part of that, there will be a migration from the os-ext-testing-data config
repo to use a repo following the structure of [project-config] (https://github.com/openstack-infra/project-config/).

Fortunately, that task is simple:

1. Create a new repo called e.g. project-config-ci-name

2. mkdir zuul

3. cp ~/os-ext-testing-data/etc/zuul/layout.yaml ~/project-config-ci-name/zuul/

4. cp ~/os-ext-testing/puppet/modules/os_ext_testing/files/zuul/openstack_functions.py ~/project-config-ci-name/zuul/

5. update os-ext-testing-data/vars.sh to include export PROJECT_CONFIG=http://your_git_url/project-config-ci-name.git

6. Push the changes. They'll be checked out in /etc/project-config

NEW 7/17/2015 - Now using common-Jenkins Job Builder

7. cp -R ~/os-ext-testing-data/etc/jenkins_jobs/config/* ~/project-config-ci-name/jenkins/jobs

8. Push the changes. They'll be checked out in /etc/project-config

NEW 8/24/2015 - Migrate nodepool configuration files to project-config

There are a few big changes here. First, previously, the nodepool.yaml file was a template where some portions where
populated by puppet. After migrating, the nodepool.yaml will be a static file containing all usernames and credentials.

Second, previously the nodepool elements and scripts used to build nodepool images were copied from http://git.openstack.org/cgit/openstack-infra/project-config/tree/nodepool.
The puppet scripts allowed you to override and add additional scripts/elements in your os-ext-testing-data repository. This is no
longer supported. Instead, you manually fork the scripts and elements and maintain them separately.


9. cd ~/project-config-ci-name/

10. mkdir nodepool

11. If you already have a nodepool.yaml file create previously, copy it from /etc/nodepool to ~/project-config-ci-name/nodepool
otherwise, create a new one taking care to ensure all values are fully resolved. [Nodepool Configuration Manual] 
(http://docs.openstack.org/infra/nodepool/configuration.html)

12. If you already have scripts/elemements in /etc/nodepool, copy them over to  ~/project-config-ci-name/nodepool/elements and
 ~/project-config-ci-name/nodepool/scripts.
Otherwise, start with the scripts/elements provided [by upstream's project config] (http://git.openstack.org/cgit/openstack-infra/project-config/tree/nodepool
) and adjust to make them work in your environment.

13. Remove any remaining values in your previous os-ext-testing-data/vars.sh such as PROVIDER_.*


## Support

If you need help, you can:

1. Submit a question/issue via github

2. Ask in the [third party ci meetings](https://wiki.openstack.org/wiki/Meetings/ThirdParty#Weekly_Third_Party_meetings)

3. Ask in the [mailing list](http://lists.openstack.org/cgi-bin/mailman/listinfo/openstack-dev). Use [third-party] tag in the subject. 

4. Ask on [IRC freenode](https://wiki.openstack.org/wiki/IRC) in channel #openstack-infra

## Pre-requisites

The following are pre-requisite steps before you install anything:

1. Read the official documentation: http://ci.openstack.org/third_party.html

2. Get a Gerrit account for your testing system registered

3. Ensure base packages installed on your target hosts/VMs

4. Set up your data repository

Below are detailed instructions for each step.

### Registering an Upstream Gerrit Account

You will need to register a Gerrit account with the upstream OpenStack
CI platform. You can read the instructions for doing
[that](http://ci.openstack.org/third_party.html#requesting-a-service-account)

### Ensure Basic Packages on Hosts/VMs

We will be installing a Jenkins master server and infrastructure on one
host or virtual machine and one or more Jenkins slave servers on hosts or VMs.

On each of these target nodes, you will want the base image to have the 
`wget`, `openssl`, `ssl-cert` and `ca-certificates` packages installed before
running anything in this repository.

### Set Up Your Data Repository 

NOTE: This section is a out-dated because of the migration towards the common-ci solution & project-config. See 
those details at the top of this README.

You will want to create a Git repository containing configuration data files -- such as the
Gerrit username and private SSH key file for your testing account -- that are used
in setting up the test platform.

The easiest way to get your data repository set up is to make a copy of the example
repository I set up here:

http://github.com/rasselin/os-ext-testing-data

and put it somewhere private. There are a few things you will need to do in this
data repository:

1. Copy the **private** SSH key that you submitted when you registered with the upstream
   OpenStack Infrastructure team into somewhere in this repo.

2. If you do not want to use the SSH key pair in the `os-ext-testing-data` example
   data repository and want to create your own SSH key pair, do this step.

   Create an SSH key pair that you will use for Jenkins. This SSH key pair will live
   in the `/var/lib/jenkins/.ssh/` directory on the master Jenkins host, and it will
   be added to the `/home/jenkins/.ssh/authorized_keys` file of all slave hosts::

    ssh-keygen -t rsa -b 1024 -N '' -f jenkins_key

   Once you do the above, copy the `jenkins_key` and `jenkins_key.pub` files into your
   data repository.

3. Copy the vars.sh.sample to vars.sh and open up `vars.sh` in an editor.

4. Change the value of the `$UPSTREAM_GERRIT_USER` shell
   variable to the Gerrit username you registered with the upstream OpenStack Infrastructure
   team [as detailed in these instructions](http://ci.openstack.org/third_party.html#requesting-a-service-account)

5. Change the value of the `$UPSTREAM_GERRIT_SSH_KEY_PATH` shell variable to the **relative** path
   of the private SSH key file you copied into the repository in step #2.

   For example, let's say you put your private SSH key file named `mygerritkey` into a directory called `ssh`
   within the repository, you would set the `$UPSTREAM_GERRIT_SSH_KEY_PATH` value to
   `ssh/mygerritkey`

6. If for some reason, in step #2 above, you either used a different output filename than `jenkins_key` or put the
   key pair into some subdirectory of your data repository, then change the value of the `$JENKINS_SSH_KEY_PATH`
   variable in `vars.sh` to an appropriate value.

7. Copy etc/nodepool/nodepool.yaml.erb.sample to etc/nodepool/nodepool.yaml.erb. Adjust as needed according to docs: http://ci.openstack.org/nodepool/configuration.html.  
8. Update etc/zuul/layout.yaml according to docs: http://ci.openstack.org/zuul/zuul.html#layout-yaml

## Usage

### Setting up the Jenkins Master

#### Installation

On the machine you will use as your Jenkins master, run the following:

```
wget https://raw.github.com/rasselin/os-ext-testing/master/puppet/install_master.sh
bash install_master.sh
```

The script will install Puppet, create an SSH key for the Jenkins master, create
self-signed certificates for Apache, and then will ask you for the URL of the Git
repository you are using as your data repository (see Prerequisites #3 above). Enter
the URL of your data repository and hit Enter.

Puppet will proceed to set up the Jenkins master.

#### Manual setup of Jenkins scp 1.9 plugin

Version 1.8 is publicly available, but does not have all features (e.g. copy console log file, copy files after failure, etc.).
Follow these steps to manually build and install the scp 1.9 plugin:
* Download http://tarballs.openstack.org/ci/scp.jpi
* Jenkins Manage Plugins; Advanced; Upload Plugin (scp.jpi)

Source: `http://lists.openstack.org/pipermail/openstack-infra/2013-December/000568.html`

#### Restart Jenkins to get the plugins fully installed

    sudo service jenkins restart

#### Load Jenkins Up with Your Jobs

Run the following at the command line:

    sudo jenkins-jobs --flush-cache update /etc/jenkins_jobs/config

#### Configuration
Start zuul

    sudo service zuul start
    sudo service zuul-merger start

#### Configuration

After Puppet installs Jenkins and Zuul and Nodepool, you will need to do a
couple manual configuration steps in the Jenkins UI.

1. Go to the Jenkins web UI. By default, this will be `http://$IP_OF_MASTER:8080`

2. Click the `Manage Jenkins` link on the left

3. Click the `Configure System` link

4. Scroll down until you see "Gearman Plugin Config". Check the "Enable Gearman" checkbox.

5. Click the "Test Connection" button and verify Jenkins connects to Gearman.
6. Scroll to "ZMQ Event Publisher" and select "Enable on all Jobs". Double-check
 the port matches the URL configured for "zmq-publishers" in `$DATA_REPO/etc/nodepool/nodepool.yaml.erb`

7. Scroll down to the bottom of the page and click `Save`

8. At the command line, do this::

    sudo service zuul restart

### Running jobs on Jenkins Master

Currently it seems that running jobs on Jenkins Master directly no longer works. It seems to be a regression
with newer versions of Jenkins. So skip that and go straight to:


### Setting up Nodepool Jenkins Slaves

1. Re-run the install_master.sh script for your changes to take effect.

2. Make sure the jenkins key is setup in the 'cloud' provider
   with name "jenkins". TODO: make it configurable.

3. Manually create your first image. This is helpful to debug errors. On subsequent
   debug runs, consider enabling DIB_OFFLINE=true mode to save time. Remember to unset DIB_OFFLINE when creating the real image.

   See here for more information.
   [project-config DIB tips] (https://github.com/openstack-infra/project-config/tree/master/nodepool/elements)

   ```
   sudo su - nodepool
   #optional export DIB_OFFLINE=true
   nodepool image-build <image-name>
   ```

4. Start nodepool:
   ```
   sudo service nodepool start
   # Or manually (in a screen session):
   sudo su - nodepool
   source /etc/default/nodepool
   nodepoold -d $DAEMON_ARGS
   ```

### Setting up Log Server

The Log server is a simple VM with an Apache web server installed that provides http access to all the log files uploaded by the jenkins jobs. It is a separate script because the jenkins-zuul-nodepool 'master' server may/can not be publicly accessible for security reasons. In addition, separating out the log server as its own server relaxes the disk space requirements needed by the jenkins master. 

Installing the Log Server on the same VM as Jenkins/Nodepool/Zuul is not supported.

It's configuration uses the puppet-openstackci scripts, which provide the friendly log filtering features, hightlighting, the line references, etc.

For simplicity, it is recommended to use the same jenkins key for authentication.

```
wget https://raw.githubusercontent.com/rasselin/os-ext-testing/master/puppet/install_log_server.sh
export DOMAIN=your.domain.com
export JENKINS_SSH_PUBLIC_KEY=/full/path/to/public/key
#MANUALLY Update the LOG_SERVER_DOMAIN & JENKINS_SSH_PUBLIC_KEY_CONTENTS variables
bash install_log_server.sh
```

When completed, the jenkins user will be able to upload files to /srv/static/logs, which Apache will serve via http.
This is accomplished by adding publishers to your jenkins job.

For example:

[console-log] (https://github.com/rasselin/os-ext-testing/blob/master/puppet/modules/os_ext_testing/templates/jenkins_job_builder/config/macros.yaml.erb#L117)

[publisher used] (https://github.com/rasselin/os-ext-testing-data/blob/master/etc/jenkins_jobs/config/dsvm-cinder-driver.yaml.sample#L73)


