# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_transportchain) do
  @doc = <<-DOC
    @summary This manages a WebSphere Web Container Transport Chain resource.

    @example
      websphere_transportchain { 'WC_InboundWSSecure':
        ensure               => 'present',
        enabled              => true,
        template             => 'WebContainer-Secure',
        endpoint_name        => 'WC_WSHost',
        endpoint_details     => [['*', 9443]],
        tcp_inbound_channel  => tcp_hash,
        ssl_inbound_channel  => ssl_hash,
        http_inbound_channel => http_hash,
        wcc_inbound_channel  => wcc_hash,
        profile_base         => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile         => 'PROFILE_DMGR_01',
        cell                 => 'CELL_01',
        node                 => 'APPNODE_01',
        server               => 'APPSERVER_01',
        user                 => 'webadmin',
        wsadmin_user         => 'wasadmin',
        wsadmin_pass         => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # TChainName
      [
        %r{^([^:]+)$},
        [
          [:tc_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:TChainName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:tc_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:TChainName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:tc_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:TChainName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:tc_name],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be server" unless %r{^(server)$}.match?(self[:scope])
    raise ArgumentError, 'server is required when scope is server' if self[:server].nil? && self[:scope] == 'server'
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'node_name is required' if self[:node_name].nil?
    raise ArgumentError, 'server is required' if self[:server].nil?
    raise ArgumentError, 'cluster is required when scope is cluster' if self[:cluster].nil? && self[:scope] =~ %r{^cluster$}
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?
    raise ArgumentError, 'endpoint_name is required' if self[:endpoint_name].nil?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:tc_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end

    # Do not set the EndPointName inside the tcp_inbound_channel - we will use the one set at the resource level.
    raise Puppet::Error, 'Puppet::Type::Websphere_TransportChain: tcp_inbound_channel must not contain the end_point_name parameter. The `endpoint_name` parameter will be used instead.' if ( !self[:tcp_inbound_channel].nil? && self[:tcp_inbound_channel].key?(:endPointName) )


    # If we are not using a secure template but we are passing the ssl inbound channel params - we need to bail.
    if self[:template] == :'WebContainer' && self[:ssl_inbound_channel] != {}
      raise Puppet::Error, "Puppet::Type::Websphere_TransportChain: Argument error in ssl_inbound_channel: cannot use with an insecure HTTP template"
    end
  end

  newparam(:tc_name) do
    isnamevar
    desc <<-EOT
    Required. The Web Container Transport Chain name to create/modify/remove.
    
    Example: `WC_InboundWSSecure`
    EOT
  end

  newproperty(:enabled) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional. Whether Transport Chain is enabled or disabled. Defaults to `true`'
  end

  newparam(:template) do
    defaultto :'WebContainer-Secure'
    newvalues(:WebContainer, :'WebContainer-Secure')
    desc <<-EOT
    Optional. The creation template used for the given Transport Chain. Defaults to `WebContainer-Secure`

    Note: the template cannot be changed after the object has been created. Delete the object and
          re-create it with the desired template.
    EOT
  end

  newproperty(:endpoint_name) do
    desc 'Required. The endpoint config name to bind this Transport Chain to. Can be an existing one, or a new one'
  end

  newparam(:endpoint_details, :array_matching => :all) do
    desc 'Optional. If a new endpoint configuration is to be created - specify a [`host`, `port`] pair.'
  end

  newproperty(:tcp_inbound_channel) do
    desc "A hash table containing the TCP inbound channel settings. See Working with TCP inbound channel properties files documentation"

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
      raise Puppet::Error, 'Puppet::Type::Websphere_TransportChain: tcp_inbound_channel property must be a hash' unless value.kind_of?(Hash)
    end

    # Because of their number and complexity, there's only so much we can do before we let the users hurt themselves.
    munge do |value|
      munged_values={}
      value.each do |k, v|
        # camelCase and convert our hash keys to symbols.
        k_sym = k.split('_').inject{|m, p| m + p.capitalize}.to_sym
        munged_values[k_sym] = v
      end
      munged_values
    end
  end

  newproperty(:ssl_inbound_channel) do
    desc 'A hash table containing the SSL inbound channel settings. See Working with SSL inbound channel properties files documentation'
    default_mapping_data = { 
      :mapping_config_alias => '',
      :auth_data_alias => ''
    }
    defaultto default_mapping_data   

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
      raise Puppet::Error, 'Puppet::Type::Websphere_TransportChain: ssl_inbound_channel property must be a hash' unless value.kind_of?(Hash)
    end

    # camelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newproperty(:http_inbound_channel) do
    desc 'A hash table containing the HTTP inbound channel settings. See Working with HTTP inbound channel properties files documentation'
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
      raise Puppet::Error, 'Puppet::Type::Websphere_TransportChain: http_inbound_channel property must be a hash' unless value.kind_of?(Hash)
    end

    # CamelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newproperty(:wcc_inbound_channel) do
    desc 'A hash table containing the WCC inbound channel settings. See Working with WCC inbound channel properties files documentation'
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
      raise Puppet::Error, 'Puppet::Type::Websphere_TransportChain: wcc_inbound_channel property must be a hash' unless value.kind_of?(Hash)
    end

    # CamelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the Web Container Transport Chain.
    Valid value: server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Web Container Transport Chain should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Web Container Transport Chain should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Web Container Transport Chain should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Web Container Transport Chain should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Web Container Transport Chain should be set under.  Basically, where
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
