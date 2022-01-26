# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_personalcert) do
  @doc = <<-DOC
    @summary This manages a WebSphere SSL Personal Certificate resource.

    @example
      websphere_personalcert { 'new_cert_alias':
        ensure             => 'present',
        key_store_name     => 'CellDefaultKeyStore',
        key_file_path      => '/some/path/to/source-keystore.p12',
        key_file_pass      => 'SourceKeyStorePassword',
        key_file_type      => 'PKCS12',
        key_file_certalias => 'SourceCertAlias',
        replace_old_cert   => 'old_cert_alias',
        delete_old_cert    => true,
        delete_old_signers => true,
        profile_base       => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile       => 'PROFILE_DMGR_01',
        cell               => 'CELL_01',
        user               => 'webadmin',
        wsadmin_user       => 'wasadmin',
        wsadmin_pass       => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # CertAlias
      [
        %r{^([^:]+)$},
        [
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:CertAlias
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CertAlias
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:CertAlias
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:CertAlias
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:CertAlias
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:cert_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:CertAlias
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:cert_alias],
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
    raise ArgumentError, "Invalid key_file_path #{self[:key_file_path]}" unless Pathname.new(self[:key_file_path]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:cert_alias, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:cert_alias) do
    isnamevar
    desc <<-EOT
    Required. The Personal Certificate alias name to create/modify/remove.
    
    Example: `www.foo.bar.baz_expiry_YYYYMMDD`
    EOT
  end

  newparam(:key_store_name) do
    desc 'Required. The name of the destination keystore for the import operation.'
  end

  newparam(:key_file_path) do
    desc 'Required. The fully qualified path on the filesystem of the source keystore from which to import the personal certificate.'
  end

  newparam(:key_file_pass) do
    desc "Required. The password to access the source keystore."
  end

  newparam(:key_file_type) do
    newvalues(:PKCS12, :JCEKS, :JKS, :CMSKS, :PKCS11)
    desc 'Required. The SSL type of the source keystore. One of the following: `PKCS12`, `JCEKS`, `JKS`, `CMSKS`, `PKCS11` '
  end

  newparam(:key_file_certalias) do
    desc "Required. The personal certificate alias name to import from the source keystore."
  end

  newparam(:replace_old_cert) do
    desc <<-EOT
    Optional. Set the value of this parameter to the name of the old certificate to replace with the newly imported one.
    
    Example: `www.foo.bar.baz_expired`
    EOT
  end

  newparam(:delete_old_cert) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Set the value of this parameter to true in order to delete the old certificates during certificate replacement. Defaults to `false`'
  end

  newparam(:delete_old_signers) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Set the value of this parameter to true in order to delete the old signer certificates during certificate replacement. Defaults to `false`'
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the Personal Certificate .
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Personal Certificate should be set'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Personal Certificate should be set'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Personal Certificate should be set'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Personal Certificate should be set'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Personal Certificate should be set under.  Basically, where
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