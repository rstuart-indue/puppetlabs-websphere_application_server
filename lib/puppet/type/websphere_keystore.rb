# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_keystore) do
  @doc = <<-DOC
    @summary This manages a WebSphere SSL Keystore resource.

    @example
      websphere_keystore { 'puppet_keystore':
        ensure           => 'present',
        description      => 'Puppet Test Keystore',
        usage            => 'SSLKeys',
        location         => '/some/path/to/puppet-keystore.p12',
        type             => 'PKCS12',
        store_password   => 'SomeRandomPassword',
        readonly         => false,
        init_at_startup  => false,
        enable_crypto_hw => false,
        profile_base     => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile     => 'PROFILE_DMGR_01',
        cell             => 'CELL_01',
        user             => 'webadmin',
        wsadmin_user     => 'wasadmin',
        wsadmin_pass     => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # KSName
      [
        %r{^([^:]+)$},
        [
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:KSName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:KSName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:KSName
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:KSName
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:KSName
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:ks_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:KSName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:ks_name],
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

    [:ks_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:ks_name) do
    isnamevar
    desc <<-EOT
    Required. The Keystore  name to create/modify/remove.
    
    Example: `QASEvents`
    EOT
  end

  newproperty(:description) do
    desc 'Required. A meanigful description of the Keystore object.'
  end

  newproperty(:usage) do
    defaultto :SSLKeys
    newvalues(:SSLKeys, :RootKeys, :DefaultSigners, :RSATokenKeys, :KeySetKeys)
    desc 'Optional. The SSL Keystore purpose. One of the following: `SSLKeys`, `RootKeys`, `DefaultSigners`, `RSATokenKeys`, `KeySetKeys`. Defaults to `SSLKeys`'
  end

  newproperty(:location) do
    desc 'Required. The Keystore location on the filesystem. Can be referencing a WAS variable or an absolute path.'
  end

  newproperty(:type) do
    newvalues(:PKCS12, :JCEKS, :JKS, :CMSKS, :PKCS11)
    desc 'Required. The SSL Keystore type. One of the following: `PKCS12`, `JCEKS`, `JKS`, `CMSKS`, `PKCS11` '
  end

  newproperty(:store_password) do
    desc "Required. The KeyStore password."
  end

  newproperty(:readonly) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Whether the KeyStore is read-only. Defaults to `false`'
  end

  newproperty(:init_at_startup) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Whether the KeyStore is initialized at startup. Defaults to `false`'
  end

  newproperty(:enable_crypto_hw) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Whether a hardware cyptographic device is used for cryptographic operations only. Operations requiring login are not supported when using this option. Defaults to `false`'
  end

  newproperty(:enable_stashfile) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Whether to create stash files for CMS type keystore. Defaults to `false`'
  end

  newproperty(:remote_hostlist) do
    defaultto ''
    desc 'Optional. Specifies a host (or list of hosts) to contact to perform the key store operation. Multiple hosts may be listed, separated by a "|" character. Defaults to an empty, 0-length string - no hosts'
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the Keystore .
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Keystore should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Keystore should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Keystore should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Keystore should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Keystore should be set under.  Basically, where
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