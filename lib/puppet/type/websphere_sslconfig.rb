# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_sslconfig) do
  @doc = <<-DOC
    @summary This manages a WebSphere SSL Config resource.

    @example
      websphere_sslconfig { 'ssl_config_name':
        ensure            => 'present',
        key_store_name    => 'CellDefaultKeyStore',
        key_store_scope   => 'cell',
        trust_store_name  => 'CellDefaultTrustStore',
        trust_store_scope => 'cell',
        server_cert_alias => 'ServerCert_alias',
        client_cert_alias => 'ClientCert_alias',
        client_auth_req   => true,
        client_auth_supp  => true,
        security_level    => 'HIGH',
        enabled_ciphers   => '',
        ssl_protocol      => 'TLSv1.3',
        type              => 'JSSE',
        jsse_provider     => 'IBMJSSE2',
      # tk_managers       => $trust_key_managers,
      # sssl_config       => $sssl_hash,
      # config_properties => $extra_ssl_config_props,
        profile_base      => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile      => 'PROFILE_DMGR_01',
        cell              => 'CELL_01',
        user              => 'webadmin',
        wsadmin_user      => 'wasadmin',
        wsadmin_pass      => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # ConfigAlias
      [
        %r{^([^:]+)$},
        [
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:ConfigAlias
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:ConfigAlias
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:ConfigAlias
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:ConfigAlias
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:ConfigAlias
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:conf_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:ConfigAlias
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:conf_alias],
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

    # Default the key and trust stores scopes to the resource SSL Config scope.
    self[:key_store_scope] = self[:scope] if self[:key_store_scope].nil?
    self[:trust_store_scope] = self[:scope] if self[:trust_store_scope].nil?

    [:conf_alias, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:conf_alias) do
    isnamevar
    desc <<-EOT
    Required. The SSL Config alias name to create/modify/remove.
    
    Example: `Puppet_SSL_Custom_Config`
    EOT
  end

  newproperty(:key_store_name) do
    desc 'Required. The name of the key store associated with this SSL configuration.'
  end

  newproperty(:trust_store_name) do
    desc 'Required. The name of the trust store associated with this SSL configuration.'
  end

  newproperty(:server_key_alias) do
    defaultto ''
    desc 'Optional. Specifies the certificate alias that is used as the identity for this SSL configuration. Defaults to `` (empty string)'
  end

  newproperty(:client_key_alias) do
    defaultto ''
    desc 'Optional. Specifies the description for a client certificate alias associated with this SSL configuration. Defaults to `` (empty string)'
  end

  newproperty(:key_store_scope) do
    desc 'Optional. The scope of the specified key store. Defaults to the SSL Config alias scope.'
  end

  newproperty(:trust_store_scope) do
    desc 'Optional. The scope of the specified key store. Defaults to the SSL Config alias scope.'
  end

  newproperty(:client_auth_req) do
    defaultto false
    newvalues(true, false)
    desc 'Optional. Set the value of this parameter to `true` to request client authentication. Defaults to `false`'
  end

  newproperty(:client_auth_supp) do
    defaultto false
    newvalues(true, false)
    desc 'Optional. Set the value of this parameter to `true` to support client authentication. Defaults to `false`'
  end

  newproperty(:security_level) do
    defaultto :HIGH
    newvalues(:HIGH, :MEDIUM, :LOW, :CUSTOM)
    desc 'Optional. The cipher group that you want to use. Valid values are: HIGH, MEDIUM, LOW, and CUSTOM. Defaults to `HIGH`'
  end

  newproperty(:enabled_ciphers) do
    defaultto ''
    desc 'Optional. A list of accepted ciphers used during the SSL handshake. Defaults to an empty string: `` i.e. all, no exceptions.'
  end

  newproperty(:ssl_protocol) do
    defaultto :SSL_TLS
    newvalues(:SSL_TLS, :SSL_TLSv2, :SSL, :SSLv2, :SSLv3, :TLS, :TLSv1, :'TLSv1.2', :'TLSv1.3')
    desc <<-EOT
    Optional. The protocol type for the SSL handshake. Valid values include:
      - SSL_TLS
      - SSL_TLSv2
      - SSL
      - SSLv2
      - SSLv3
      - TLS
      - TLSv1
      - TLSv1.2
      - TLSv1.3 - for WAS 9.0.5.7 or later
    
    Defaults to `SSL_TLS` which supports all handshake protocols except for SSLv2 on the server side.
    EOT
  end

  # TODO: Implement the trust/key manager names and scopes. This isn't something which changes on a dime, and
  #       as such, a Cptn. Default is sufficient.
  # TODO: Implement SSL Config Properties (a big can of worms in itself because it uses the AdminConfig object, not specific commands)
  #       Perhaps this should be a separate type?
  #
  # newproperty(:config_properties) do
  #   desc <<-EOT
  #   Optional. Creates a named property (key-value pair) for the SSL configuration.
  #   Use this command to set SSL configuration settings that are different from the settings in the SSL configuration object.
  #   EOT
  # end

  newparam(:type) do
    defaultto :JSSE
    desc 'Optional. Specifies type of the SSL configuration. Defaults to `JSSE`'
  end

  newproperty(:jsse_provider) do
    defaultto :IBMJSSE2
    desc 'Optional. Specifies JSSE provider of the SSL configuration. Defaults to `IBMJSSE2`'
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the SSL Config .
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this SSL Config should be set'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this SSL Config should be set'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this SSL Config should be set'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this SSL Config should be set'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this SSL Config should be set under.  Basically, where
    are we finding `wsadmin`

    This is synonymous with the 'profile' parameter.

    Example: dmgrProfile01"
    EOT
  end

  newparam(:profile_base) do
    isnamevar
    desc "The base directory where profiles are stored.
      Example: /opt/IBM/WebSphere/AppServer/profiles"
  end

  newparam(:user) do
    defaultto 'root'
    desc "The user to run 'wsadmin' with"
  end

  newparam(:wsadmin_user) do
    desc 'The username for wsadmin authentication'
  end

  newparam(:wsadmin_pass) do
    desc 'The password for wsadmin authentication'
  end
end