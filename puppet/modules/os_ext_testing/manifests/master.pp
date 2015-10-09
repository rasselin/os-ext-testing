# Puppet module that installs Jenkins, Zuul, Jenkins Job Builder,
# and installs JJB and Zuul configuration files from a repository
# called the "data repository".

class os_ext_testing::master (
  $vhost_name = $::fqdn,
  $data_repo_dir = '',
  $serveradmin = "webmaster@${::fqdn}",
  $jenkins_ssh_private_key = '',
  $jenkins_ssh_public_key = '',
  $jenkins_ssh_public_key_no_whitespace = '',
  $smtp_host = 'localhost',
  $publish_host = 'localhost',
  $zuul_host = $::ipaddress,
  $url_pattern = "http://$publish_host/{build.parameters[LOG_PATH]}",
  $log_root_url= "$publish_host",
  $static_root_url= "$publish_host/static",
  $upstream_gerrit_server = 'review.openstack.org',
  $gearman_server = '127.0.0.1',
  $upstream_gerrit_user = '',
  $upstream_gerrit_ssh_private_key = '',
  $upstream_gerrit_ssh_host_key = '',
  $upstream_gerrit_baseurl = '',
  $git_email = 'testing@myvendor.com',
  $git_name = 'MyVendor Jenkins',
  $mysql_root_password = '',
  $mysql_password = '',
  $provider_username = 'admin',
  $provider_password = 'password',
  $provider_image_name = 'trusty',
  $provider_image_setup_script_name = 'prepare_node_devstack.sh',
  $jenkins_api_user = 'jenkins',
  $jenkins_api_password = '',
  # The Jenkins API Key is needed if you have a password for Jenkins user inside Jenkins
  $jenkins_api_key = 'abcdef1234567890',
  # The Jenkins credentials_id should match the id field of this element:
  # <com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.6">
  # inside this file:
  # /var/lib/jenkins/credentials.xml
  # which is the private key used by the jenkins master to log into the jenkins
  # slave node to install and register the node as a jenkins slave
  $jenkins_credentials_id = 'abcdef-0123-4567-89abcdef0123',
  $project_config_repo = '',
  $zuul_revision = 'master',
  $zuul_git_source_repo = 'https://git.openstack.org/openstack-infra/zuul',
  $nodepool_revision = 'master',
  $nodepool_git_source_repo = 'https://git.openstack.org/openstack-infra/nodepool',
) {
  include os_ext_testing::base

  class { '::openstackci::jenkins_master':
    vhost_name              => "jenkins",
    serveradmin             => $serveradmin,
    logo                    => 'openstack.png',
    jenkins_ssh_private_key => $jenkins_ssh_private_key,
    jenkins_ssh_public_key  => $jenkins_ssh_public_key,
    manage_jenkins_jobs     => true,
    jenkins_url             => 'http://127.0.0.1:8080/',
    jenkins_username        => $jenkins_api_user,
    jenkins_password        => $jenkins_api_password,
    project_config_repo     => $project_config_repo,
  }

  #Extra, not part of openstack upstream:
  jenkins::plugin { 'rebuild':
    version => '1.14',
  }

  #TODO: Restart jenkins after plugins are installed
  #TODO: Ensure Jenkins is started before loading jenkins jobs

  file { '/etc/jenkins_jobs/config/macros.yaml':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    content => template('os_ext_testing/jenkins_job_builder/config/macros.yaml.erb'),
    notify  => Exec['jenkins_jobs_update'],
  }

  class { '::openstackci::zuul_merger':
    vhost_name               => $zuul_host,
    gearman_server           => $gearman_server,
    gerrit_server            => $upstream_gerrit_server,
    gerrit_user              => $upstream_gerrit_user,
    known_hosts_content      => "", # Leave blank as it is set by openstackci::zuul_scheduler
    zuul_ssh_private_key     => $upstream_gerrit_ssh_private_key,
    zuul_url                 => "http://$zuul_host/p/",
    git_email                => $git_email,
    git_name                 => $git_name,
    manage_common_zuul       => false,
    revision                 => $zuul_revision,
    git_source_repo          => $zuul_git_source_repo,
  }

  class { '::openstackci::zuul_scheduler':
    vhost_name                     => $zuul_host,
    gearman_server                 => $gearman_server,
    gerrit_server                  => $upstream_gerrit_server,
    gerrit_user                    => $upstream_gerrit_user,
    known_hosts_content            => $upstream_gerrit_ssh_host_key,
    zuul_ssh_private_key           => $upstream_gerrit_ssh_private_key,
    url_pattern                    => $url_pattern,
    zuul_url                       => "http://$zuul_host/p/",
    job_name_in_report             => true,
    status_url                     => "http://$zuul_host",
    swift_authurl                  => $swift_authurl,
    swift_auth_version             => $swift_auth_version,
    swift_user                     => $swift_user,
    swift_key                      => $swift_key,
    swift_tenant_name              => $swift_tenant_name,
    swift_region_name              => $swift_region_name,
    swift_default_container        => $swift_default_container,
    swift_default_logserver_prefix => $swift_default_logserver_prefix,
    swift_default_expiry           => $swift_default_expiry,
    proxy_ssl_cert_file_contents   => $proxy_ssl_cert_file_contents,
    proxy_ssl_key_file_contents    => $proxy_ssl_key_file_contents,
    proxy_ssl_chain_file_contents  => $proxy_ssl_chain_file_contents,
    statsd_host                    => $statsd_host,
    project_config_repo            => $project_config_repo,
    git_email                      => $git_email,
    git_name                       => $git_name,
    smtp_host                      => $smtp_host,
    revision                       => $zuul_revision,
#    git_source_repo                => $zuul_git_source_repo,
  }

  # We need to make sure the configuration is correct before reloading zuul,
  # Otherwise the zuul process could get into a bad state that is difficult
  # to debug
  exec { 'zuul-check-reload':
    command     => '/usr/local/bin/zuul-server -t',
    logoutput   => on_failure,
    require     => File['/etc/init.d/zuul'],
    refreshonly => true,
    notify      => Exec['zuul-reload'],
  }

# TODO: Why use the Jenkins ssh_config also for zuul ?
# Upstream doesn't do this, so let's take it out.
  file { '/home/zuul/.ssh/config':
    ensure  => present,
    owner   => 'zuul',
    group   => 'zuul',
    mode    => '0700',
    require => File['/home/zuul/.ssh'],
    source  => 'puppet:///modules/jenkins/ssh_config',
  }

  class { '::openstackci::nodepool':
    mysql_root_password       => $mysql_root_password,
    mysql_password            => $mysql_password,
    nodepool_ssh_private_key  => $jenkins_ssh_private_key,
    revision                  => $nodepool_revision,
    git_source_repo           => $nodepool_git_source_repo,
    oscc_file_contents        => '',
    environment               => {
      # Set up the key in /etc/default/nodepool, used by the service.
      'NODEPOOL_SSH_KEY'      => $jenkins_ssh_public_key_no_whitespace,
    },
    project_config_repo       => $project_config_repo,
    enable_image_log_via_http => false,
    jenkins_masters           => [
      { name => 'local-jenkins',
        url => 'http://localhost:8080/',
        user => $jenkins_api_user,
        apikey => $jenkins_api_key,
        credentials => $jenkins_credentials_id,
      },
    ],
  }

  file {"/var/lib/jenkins/credentials.xml":
      ensure => present,
      owner  => 'jenkins',
      group  => 'jenkins',
      mode   => '0644',
      content => template('os_ext_testing/jenkins/credentials.xml.erb'),
  }

  file {"/var/lib/jenkins/be.certipost.hudson.plugin.SCPRepositoryPublisher.xml":
      ensure => present,
      owner  => 'jenkins',
      group  => 'jenkins',
      mode   => '0644',
      content => template('os_ext_testing/jenkins/be.certipost.hudson.plugin.SCPRepositoryPublisher.xml.erb'),
  }

  # FIXME: Any changes currently require jenkins to be restarted. For now, use and alert.
  exec { 'jenkins_restart_scp':
      path    => "/usr/local/bin/:/bin:/usr/sbin",
      command => 'echo "Jenkins must be manually restarted in order for SCPRepositoryPublisher changes to take affect." ',
      logoutput => "true",
      refreshonly => true,
      loglevel => 'alert',
      subscribe => File['/var/lib/jenkins/be.certipost.hudson.plugin.SCPRepositoryPublisher.xml']
  }
}

