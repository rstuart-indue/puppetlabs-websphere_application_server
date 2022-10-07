# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_jdbc_datasource) do
  @doc = <<-DOC
    @summary Manages datasources.
    @example Create a datasource at the node scope
      websphere_jdbc_datasource { 'Puppet Test':
        ensure                        => 'present',
        dmgr_profile                  => 'PROFILE_DMGR_01',
        profile_base                  => '/opt/IBM/WebSphere/AppServer/profiles',
        user                          => 'webadmin',
        scope                         => 'node',
        cell                          => 'CELL_01',
        node_name                     => 'appNode01',
        server                        => 'AppServer01',
        jdbc_provider                 => 'Puppet Test',
        jndi_name                     => 'myTest',
        data_store_helper_class       => 'com.ibm.websphere.rsadapter.Oracle11gDataStoreHelper',
        container_managed_persistence => true,
        component_managed_auth_alias  => 'dblogin_alias',
        xa_recovery_auth_alias        => 'dblogin_alias',
        mapping_configuration_alias   => 'DefaultPrincipalMapping',
        container_managed_auth_alias  => 'dblogin_alias',
        conn_pool_data                => $jdbc_connection_pool_hash
        url                           => 'jdbc:oracle:thin:@//localhost:1521/sample',
        description                   => 'Created by Puppet',
      }

      Where the connection pool data hash looks like below:
      $jdbc_connection_pool_hash {
        connection_timeout => 180,
        max_connections    => 120,
        unused_timeout     => 1800,
        min_connections    => 1,
        aged_timeout       => 300,
        purge_policy       => 'EntirePool',
        reap_time          => 180,
      }
    DOC

  autorequire(:user) do
    self[:user]
  end

  autorequire(:websphere_jdbc_provider) do
    self[:jdbc_provider]
  end

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # DSName
      [
        %r{^([^:]+)$},
        [
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:DSName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:DSName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:DSName
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:DSName
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:DSName
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:ds_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:DSName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:ds_name],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be cell, cluster, node, or server" unless %r{^(cell|cluster|node|server)$}.match?(self[:scope])
    raise ArgumentError, 'server is required when scope is server' if self[:server].nil? && self[:scope] == 'server'
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'node_name is required when scope is server, or node' if self[:node_name].nil? && self[:scope] =~ %r{(server|node)}
    raise ArgumentError, 'cluster is required when scope is cluster' if self[:cluster].nil? && self[:scope] =~ %r{^cluster$}
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:ds_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:ds_name) do
    isnamevar
    desc 'The name of the datasource'
  end

  newparam(:jdbc_provider) do
    desc <<-EOT
    The name of the JDBC Provider to use.
    EOT
  end

  newparam(:jndi_name) do
    desc <<-EOT
    The JNDI name.
    This corresponds to the wsadmin argument '-jndiName'

    Example: 'jdbc/foo'
    EOT
  end

  newparam(:data_store_helper_class) do
    desc <<-EOT
    Example: 'com.ibm.websphere.rsadapter.Oracle11gDataStoreHelper'
    EOT
  end

  newparam(:container_managed_persistence) do
    desc <<-EOT
    Use this data source in container managed persistence (CMP)

    Boolean: true or false
    EOT
    newvalues(:true, :false)
    defaultto :true
  end

  newproperty(:component_managed_auth_alias) do
    desc <<-EOT
    The alias used for database authentication at run time.
    This alias is only used when the application resource
    reference is using res-auth=Application.

    String: Optional
    EOT
    defaultto ''
  end

  newproperty(:xa_recovery_auth_alias) do
    desc <<-EOT
    This parameter is used to specify the authentication alias used during XA recovery processing.
    If this alias name is changed after a server failure, the subsequent XA recovery processing 
    uses the original setting that was in effect before the failure.

    String: Optional
    EOT
    defaultto ''
  end

  newproperty(:mapping_configuration_alias) do
    desc <<-EOT
    Specifies the authentication alias for the Java Authentication and Authorization Service (JAAS)
    mapping configuration that is used by this connection factory.

    The DefaultPrincipalMapping JAAS configuration maps the authentication alias to the user ID
    and password. You use other already defined mapping configurations.

    String: Optional
    EOT
    defaultto ''
  end

  newproperty(:container_managed_auth_alias) do
    desc <<-EOT
    Specifies authentication data, which is a JAAS - J2C authentication data entry, for container-managed
    signon to the JDBC resource.
    
    Depending on the value selected for the Mapping Configuration Alias setting, you can disable this
    setting

    String: Optional
    EOT
    defaultto ''
  end

  newproperty(:conn_pool_data) do
    desc 'A hash containing the JDBC Connection Pool settings'
    def insync?(is)
      # There will almost always be more properties on the system than
      # defined in the resource. Make sure the properties in the resource
      # are insync
      should.each_pair do |prop,value|
        return false unless (value.to_s.empty? || is.key?(prop))
        # Stop after the first out of sync property
        return false unless (property_matches?(is[prop],value) || ((is[prop].nil? || is[prop].empty?) && value.to_s.empty?))
      end
      true
    end

    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_jdbc_datasource: conn_pool_data property must be a hash' unless value.kind_of?(Hash)
    end

    # CamelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newproperty(:url) do
    desc <<-EOT
    JDBC URL for Oracle providers.

    This is only relevant when the 'data_store_helper_class' is:
      'com.ibm.websphere.rsadapter.Oracle11gDataStoreHelper'

    Example: 'jdbc:oracle:thin:@//localhost:1521/sample'
    EOT
    defaultto ''
  end

  newparam(:description) do
    desc <<-EOT
    A description for the data source
    EOT
  end

  newparam(:db2_driver) do
    desc <<-EOT
    The driver for DB2.

    This only applies when the 'data_store_helper_class' is
    'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
    EOT
  end

  newparam(:database) do
    desc <<-EOT
    The database name for DB2 and Microsoft SQL Server.

    This is only relevant when the 'data_store_helper_class' is one of:
      'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
      'com.ibm.websphere.rsadapter.MicrosoftSQLServerDataStoreHelper'
    EOT
  end

  newparam(:db_server) do
    desc <<-EOT
    The database server address.

    This is only relevant when the 'data_store_helper_class' is one of:
      'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
      'com.ibm.websphere.rsadapter.MicrosoftSQLServerDataStoreHelper'
    EOT
  end

  newparam(:db_port) do
    desc <<-EOT
    The database server port.

    This is only relevant when the 'data_store_helper_class' is one of:
      'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
      'com.ibm.websphere.rsadapter.MicrosoftSQLServerDataStoreHelper'
    EOT
  end

  newparam(:dmgr_profile) do
    isnamevar
    desc <<-EOT
    The dmgr profile that this should be created under"
    Example: dmgrProfile01"
    EOT
  end

  newparam(:profile) do
    desc <<-EOT
      Optional. The profile of the server to use for executing wsadmin
      commands. Will default to dmgr_profile if not set.
    EOT
  end

  newparam(:profile_base) do
    isnamevar
    desc <<-EOT
    The base directory that profiles are stored.
    Basically, where can we find the 'dmgr_profile' so we can run 'wsadmin'

    Example: /opt/IBM/WebSphere/AppServer/profiles"
    EOT
  end

  newparam(:user) do
    defaultto 'root'
    desc "The user to run 'wsadmin' with"
  end

  newparam(:node_name) do
    isnamevar
    desc 'The name of the node to create this application server on'
  end

  newparam(:server) do
    isnamevar
    desc 'The name of the server to create this application server on'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The name of the cluster to create this application server on'
  end

  newparam(:cell) do
    isnamevar
    desc 'The name of the cell to create this application server on'
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope to manage the JDBC Datasource at.
    Valid values are: node, server, cell, or cluster
    EOT
  end

  newparam(:wsadmin_user) do
    desc 'The username for wsadmin authentication'
  end

  newparam(:wsadmin_pass) do
    desc 'The password for wsadmin authentication'
  end
end
