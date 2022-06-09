# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_sslconfiggroup) do
  @doc = <<-DOC
    @summary This manages a WebSphere SSL Config Group resource.

    @example
      websphere_sslconfiggroup { 'ssl_config_group':
        ensure            => 'present',
        direction         => 'oubound',
        ssl_config_name   => 'CellDefaultSSLSettings',
        ssl_config_scope  => 'cell',
        client_cert_alias => 'ClientCert_alias',
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
      # ConfigGroupAlias
      [
        %r{^([^:]+)$},
        [
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:outbound:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:direction],
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:outbound:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:direction],
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:outbound:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:direction],
          [:confgrp_alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:outbound:ConfigGroupAlias
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:direction],
          [:confgrp_alias],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be cell, cluster, node, or server" unless %r{^(cell|cluster|node|server)$}.match?(self[:scope])
    raise ArgumentError, 'server is required when scope is server' if self[:server].nil? && self[:scope] == 'server'
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'direction is required' if self[:direction].nil?
    raise ArgumentError, 'node_name is required when scope is server, or node' if self[:node_name].nil? && self[:scope] =~ %r{(server|node)}
    raise ArgumentError, 'cluster is required when scope is cluster' if self[:cluster].nil? && self[:scope] =~ %r{^cluster$}
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    # Default the SSL Config scope to the resource SSL Config Group scope.
    self[:ssl_config_scope] = self[:scope] if self[:ssl_config_scope].nil?

    [:confgrp_alias, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:confgrp_alias) do
    isnamevar
    desc <<-EOT
    Required. The SSL Config Group alias name to create/modify/remove.
    
    Example: `Puppet_SSL_Custom_Config_Group`
    EOT
  end

  newparam(:direction) do
    isnamevar
    newvalues(:inbound, :outbound)
    desc 'Required. The direction of the SSL Config Group. Valid values: inbound, outbound'
  end

  newproperty(:ssl_config_name) do
    desc 'Required. The name of the SSL configuration associated with the SSL Config Group'
  end

  newproperty(:ssl_config_scope_type) do
    newvalues(:cell, :cluster, :node, :server)
    desc 'Required. The scope type of the associated SSL configuration. Valid values: cell, cluster, node, or server'
  end  
  
  newproperty(:client_cert_alias) do
    defaultto ''
    desc 'Optional. The name of the client cert from the associated SSL configuration. Defaults to empty string ``'
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the SSL Config Group resource.
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