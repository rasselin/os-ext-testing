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
  $publish_host = 'localhost',
  $url_pattern = 'http://localhost/{change.number}/{change.patchset}/{pipeline.name}/{job.name}/{build.number}',
  $log_root_url= "$publish_host/logs",
  $static_root_url= "$publish_host/static",
  $upstream_gerrit_server = 'review.openstack.org',
  $gerrit_server='',
  $gerrit_server_port='',
  $gearman_server = '127.0.0.1',
  $upstream_gerrit_user = '',
  $upstream_gerrit_ssh_private_key = '',
  $upstream_gerrit_host_pub_key = '',
  $git_email = 'testing@myvendor.com',
  $git_name = 'MyVendor Jenkins',
  $mysql_root_password = '',
  $mysql_password = '',
  $local_username = 'admin',
  $local_password = 'password',
  $local_01_ip = 'localhost',
  $local_02_ip = 'localhost',
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

  jenkins::plugin { 'ansicolor':
    version => '0.3.1',
  }
  jenkins::plugin { 'build-timeout':
    version => '1.10',
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
    version => '0.0.6',
  }
  jenkins::plugin { 'git':
    version => '2.2.1',
  }
  jenkins::plugin { 'git-client':
    version => '1.9.1',
  }
  jenkins::plugin { 'github-api':
    version => '1.33',
  }
  jenkins::plugin { 'github':
    version => '1.4',
  }
  jenkins::plugin { 'gerrit-trigger':
    version => '2.11.1',
  }
  jenkins::plugin { 'greenballs':
    version => '1.12',
  }
  jenkins::plugin { 'htmlpublisher':
    version => '1.0',
  }
  jenkins::plugin { 'extended-read-permission':
    version => '1.0',
  }
  jenkins::plugin { 'postbuild-task':
    version => '1.8',
  }
  jenkins::plugin { 'violations':
    version => '0.7.11',
  }
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
  jenkins::plugin { 'parameterized-trigger':
    version => '2.15',
  }
  jenkins::plugin { 'publish-over-ftp':
    version => '1.7',
  }
  jenkins::plugin { 'rebuild':
    version => '1.14',
  }
  jenkins::plugin { 'scm-api':
    version => '0.2',
  }
  jenkins::plugin { 'simple-theme-plugin':
    version => '0.2',
  }
  jenkins::plugin { 'ssh-agent':
    version => '1.4.1',
  }
  jenkins::plugin { 'timestamper':
    version => '1.3.1',
  }
  jenkins::plugin { 'token-macro':
    version => '1.10',
  }
  jenkins::plugin { 'url-change-trigger':
    version => '1.2',
  }
  jenkins::plugin { 'urltrigger':
    version => '0.24',
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
    }

    file { '/etc/jenkins_jobs/config':
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      recurse => true,
      force   => true,
      source  => 'puppet:///modules/os_ext_testing/jenkins_job_builder/config',
      notify  => Exec['jenkins_jobs_update'],
    }

    file { '/etc/jenkins_jobs/config/macros.yaml':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/jenkins_job_builder/config/macros.yaml.erb'),
      notify  => Exec['jenkins_jobs_update'],
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

  class { '::zuul':
    vhost_name           => "zuul",
    gearman_server       => $gearman_server,
    gerrit_server        => $upstream_gerrit_server,
    gerrit_user          => $upstream_gerrit_user,
    zuul_ssh_private_key => $upstream_gerrit_ssh_private_key,
    url_pattern          => $url_pattern,
    zuul_url             => $zuul_url,
    job_name_in_report   => true,
    status_url           => "http://$publish_host/zuul/status",
    statsd_host          => $statsd_host,
    git_email            => $git_email,
    git_name             => $git_name
  }

  class { '::zuul::server': }
  class { '::zuul::merger': }


  if $upstream_gerrit_ssh_pub_key != '' {
    file { '/home/zuul/.ssh':
      ensure  => directory,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0700',
      require => Class['::zuul'],
    }
    file { '/home/zuul/.ssh/known_hosts':
      ensure  => present,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0600',
      content => "[review.openstack.org]:29418,[198.101.231.251]:29418 ${upstream_gerrit_host_pub_key}",
      replace => true,
      require => File['/home/zuul/.ssh'],
    }
    file { '/home/zuul/.ssh/config':
      ensure  => present,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0700',
      require => File['/home/zuul/.ssh'],
      source  => 'puppet:///modules/jenkins/ssh_config',
    }
  }

  file { '/etc/zuul/layout.yaml':
    ensure => present,
    source  => "${data_repo_dir}/etc/zuul/layout.yaml",
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/openstack_functions.py':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/openstack_functions.py',
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/logging.conf',
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/gearman-logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/gearman-logging.conf',
    notify => Exec['zuul-reload'],
  }
  
  file { '/etc/zuul/merger-logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/merger-logging.conf',
  }

  #TODO(Ramy) err: /Stage[main]/Recheckwatch/File[/var/www/recheckwatch]/ensure:
  #change from absent to directory failed: Cannot create
  #/var/www/recheckwatch; parent directory /var/www does not exist
  # Note: It does exist...perhaps created later in the script

  class { '::recheckwatch':
    gerrit_server                => $upstream_gerrit_server,
    gerrit_user                  => $upstream_gerrit_user,
    recheckwatch_ssh_private_key => $upstream_gerrit_ssh_private_key,
  }

  file { '/var/lib/recheckwatch/scoreboard.html':
    ensure  => present,
    source  => 'puppet:///modules/openstack_project/zuul/scoreboard.html',
    require => File['/var/lib/recheckwatch'],
  }

  class { '::nodepool':
    mysql_root_password      => $mysql_root_password,
    mysql_password           => $mysql_password,
    nodepool_ssh_private_key => $jenkins_ssh_private_key,
    environment              => {
      #TODO(Ramy) this doesn't seem to do anything...
      'NODEPOOL_SSH_KEY'     => $jenkins_ssh_public_key,
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
        'puppet:///modules/os_ext_testing/nodepool',
        'puppet:///modules/openstack_project/nodepool/scripts',
      ],
  }

  #Make sure http proxy environment variables are available to all users
  file { "/etc/profile.d/set_http_proxy_env.sh":
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/nodepool/set_http_proxy_env.sh.erb'),
  }

  file { "/etc/sudoers.d/80-http-proxy":
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0440',
      source => 'puppet:///modules/os_ext_testing/sudoers/80-http-proxy',
  }

  file { "/etc/sudoers.d/90-nodepool-http-proxy":
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0440',
      source => 'puppet:///modules/os_ext_testing/sudoers/90-nodepool-http-proxy',
  }

  file { "/var/lib/jenkins/gerrit-trigger.xml":
      ensure => present,
      owner  => 'jenkins',
      group  => 'jenkins',
      mode   => '0644',
      content => template('os_ext_testing/jenkins/gerrit-trigger.xml.erb'),
  }

  file {"/var/lib/jenkins/credentials.xml":
      ensure => present,
      owner  => 'jenkins',
      group  => 'jenkins',
      mode   => '0644',
      content => template('os_ext_testing/jenkins/credentials.xml.erb'),
  }
}

