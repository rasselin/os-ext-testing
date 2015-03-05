# Puppet module that installs Jenkins, Zuul, Jenkins Job Builder,
# and installs JJB and Zuul configuration files from a repository
# called the "data repository".

class os_ext_testing::master (
  $vhost_name = $::fqdn,
  $data_repo_dir = '',
  $manage_jenkins_jobs = true,
  $ssl_cert_file_contents = '',
  $ssl_key_file_contents = '',
  $ssl_chain_file_contents = '',
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
  # The Jenkins API Key is needed if you have a password for Jenkins user inside Jenkins
  $jenkins_api_key = 'abcdef1234567890',
  # The Jenkins credentials_id should match the id field of this element:
  # <com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.6">
  # inside this file:
  # /var/lib/jenkins/credentials.xml
  # which is the private key used by the jenkins master to log into the jenkins
  # slave node to install and register the node as a jenkins slave
  $jenkins_credentials_id = 'abcdef-0123-4567-89abcdef0123',
  $http_proxy = '',
  $https_proxy = '',
  $no_proxy = '',
) {
  include os_ext_testing::base
  include apache
  include pip

  package { 'tox>=1.6,<1.7':
    ensure   => present,
    provider => pip,
    require  => Class['pip'],
  }

  # Note that we need to do this here, once instead of in the jenkins::master
  # module because zuul also defines these resource blocks and Puppet barfs.
  # Upstream probably never noticed this because they do not deploy Zuul and
  # Jenkins on the same node...
  a2mod { 'rewrite':
    ensure => present,
  }
  a2mod { 'proxy':
    ensure => present,
  }
  a2mod { 'proxy_http':
    ensure => present,
  }

  if $ssl_chain_file_contents != '' {
    $ssl_chain_file = '/etc/ssl/certs/intermediate.pem'
  } else {
    $ssl_chain_file = ''
  }

  #TODO:  sudo usermod -d /var/lib/jenkins jenkins

  group { 'jenkins' :
    ensure => present,
  }

  user { 'jenkins' :
    ensure => present,
    home   => '/var/lib/jenkins',
    shell  => '/bin/bash',
  }

  class { '::jenkins::master':
    vhost_name              => "jenkins",
    logo                    => 'openstack.png',
    ssl_cert_file           => "/etc/ssl/certs/jenkins.pem",
    ssl_key_file            => "/etc/ssl/private/jenkins.key",
    ssl_chain_file          => $ssl_chain_file,
    ssl_cert_file_contents  => $ssl_cert_file_contents,
    ssl_key_file_contents   => $ssl_key_file_contents,
    ssl_chain_file_contents => $ssl_chain_file_contents,
    jenkins_ssh_private_key => $jenkins_ssh_private_key,
    jenkins_ssh_public_key  => $jenkins_ssh_public_key,
  }

  jenkins::plugin { 'build-timeout':
    version => '1.14',
  }
  jenkins::plugin { 'copyartifact':
    version => '1.22',
  }
  jenkins::plugin { 'dashboard-view':
    version => '2.3',
  }
  jenkins::plugin { 'envinject':
    version => '1.70',
  }
  jenkins::plugin { 'gearman-plugin':
    version => '0.0.7',
  }
  jenkins::plugin { 'git':
    version => '1.1.23',
  }
  jenkins::plugin { 'greenballs':
    version => '1.12',
  }
  jenkins::plugin { 'extended-read-permission':
    version => '1.0',
  }
  jenkins::plugin { 'zmq-event-publisher':
    version => '0.0.3',
  }
#TODO: When version 1.9 is release, uncomment.
#Until then, see instructions here:
#http://lists.openstack.org/pipermail/openstack-infra/2013-December/000568.html
#Or use 1.8 which doesn't have all the features
#jenkins::plugin { 'scp':
#  version => '1.8',
#}
#  TODO(jeblair): release
#  jenkins::plugin { 'scp':
#    version => '1.9',
#  }
  jenkins::plugin { 'jobConfigHistory':
    version => '1.13',
  }
  jenkins::plugin { 'monitoring':
    version => '1.40.0',
  }
  jenkins::plugin { 'nodelabelparameter':
    version => '1.2.1',
  }
  jenkins::plugin { 'notification':
    version => '1.4',
  }
  jenkins::plugin { 'openid':
    version => '1.5',
  }
  jenkins::plugin { 'publish-over-ftp':
    version => '1.7',
  }
  jenkins::plugin { 'simple-theme-plugin':
    version => '0.2',
  }
  jenkins::plugin { 'timestamper':
    version => '1.3.1',
  }
  jenkins::plugin { 'token-macro':
    version => '1.5.1',
  }

#Extra, not part of openstack upstream:
  jenkins::plugin { 'rebuild':
    version => '1.14',
  }

  file { '/var/lib/jenkins/.ssh/config':
    ensure  => present,
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => '0640',
    require => File['/var/lib/jenkins/.ssh'],
    source  => 'puppet:///modules/jenkins/ssh_config',
  }

  if $manage_jenkins_jobs == true {
    class { '::jenkins::job_builder':
      url      => "http://127.0.0.1:8080/",
      username => 'jenkins',
      password => '',
      config_dir =>"${data_repo_dir}/etc/jenkins_jobs/config/",
    }

    file { '/etc/jenkins_jobs/config/macros.yaml':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/jenkins_job_builder/config/macros.yaml.erb'),
      notify  => Exec['jenkins_jobs_update'],
    }

    if $enable_fc != false {
      file { '/etc/jenkins_jobs/config/macros-fc.yaml':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        content => template('os_ext_testing/jenkins_job_builder/config/macros-fc.yaml.erb'),
        notify  => Exec['jenkins_jobs_update'],
      }
    }

    file { '/etc/default/jenkins':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
      source => 'puppet:///modules/openstack_project/jenkins/jenkins.default',
    }
  }



  #TODO(Restart Jenkins)

  class { 'os_ext_testing::zuul':
    vhost_name           => $zuul_host,
    smtp_host            => $smtp_host,
    gearman_server       => $gearman_server,
    gerrit_server        => $upstream_gerrit_server,
    gerrit_user          => $upstream_gerrit_user,
    gerrit_baseurl       => $upstream_gerrit_baseurl,
    gerrit_ssh_host_key => "${upstream_gerrit_ssh_host_key}",
    zuul_ssh_private_key => $upstream_gerrit_ssh_private_key,
    url_pattern          => $url_pattern,
    zuul_url             => "http://$zuul_host/p/",
    job_name_in_report   => true,
    status_url           => "http://$zuul_host",
    statsd_host          => $statsd_host,
    git_email            => $git_email,
    git_name             => $git_name,
    layout_dir  => ["${data_repo_dir}/etc/zuul/",]
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

  class { '::nodepool':
    mysql_root_password      => $mysql_root_password,
    mysql_password           => $mysql_password,
    nodepool_ssh_private_key => $jenkins_ssh_private_key,
    environment              => {
      # Set up the key in /etc/default/nodepool, used by the service.
      'NODEPOOL_SSH_KEY'     => $jenkins_ssh_public_key_no_whitespace,
    }
  }

  file { '/etc/nodepool/nodepool.yaml':
    ensure  => present,
    owner   => 'nodepool',
    group   => 'sudo',
#    mode    => '0400',
    mode    => '0660',
    content => template("os_ext_testing/nodepool/nodepool.yaml.erb"),
    require => [
      File['/etc/nodepool'],
      User['nodepool'],
    ],
  }

  file { '/etc/nodepool/scripts':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    recurse => true,
    purge   => true,
    force   => true,
    require => File['/etc/nodepool'],
    sourceselect => all,
    source  => [
        # With sourceselect => our files will take precedance when found in both
        # Our files include workarounds until some patches land in openstack/infra-config
        # As well as custom settings to ensure http proxies are taken into consideration
        "${data_repo_dir}/etc/nodepool/scripts",
        '/root/project-config/nodepool/scripts',
      ],
  }

  #Make sure http proxy environment variables are available to all users
  file { "/etc/profile.d/set_nodepool_env.sh":
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/nodepool/set_nodepool_env.sh.erb'),
  }

  file { "/etc/sudoers.d/90-nodepool-http-proxy":
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0440',
      source => 'puppet:///modules/os_ext_testing/sudoers/90-nodepool-http-proxy',
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

