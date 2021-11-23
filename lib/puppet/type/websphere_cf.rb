# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_cf) do
  @doc = <<-DOC
    @summary This manages a WebSphere JMS Queue Connection Factory resource.

    @example
      websphere_cf { 'was_qcf':
        ensure          => 'present',
        jms_provider    => 'builtin_mqprovider',
        cf_type         => 'QCF',
        description     => 'Websphere Queue Connection Factory',
        jndi_name       => 'jms/QCF',
        mapping_data    => mapping_hash,
        conn_pool_data  => connection_pool_hash,
        sess_pool_data  => session_pool_hash,
        profile_base    => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile    => 'PROFILE_DMGR_01',
        cell            => 'CELL_01',
        user            => 'webadmin',
        wsadmin_user    => 'wasadmin',
        wsadmin_pass    => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # CFName
      [
        %r{^([^:]+)$},
        [
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:CFName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CFName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:CFName
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:CFName
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:CFName
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:CFName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:cf_name],
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

    [:cf_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:cf_name) do
    isnamevar
    desc <<-EOT
    Required. The Connection Factory name to create/modify/remove.
    
    Example: `QCFEvents`
    EOT
  end

  newparam(:jms_provider) do
    defaultto 'builtin_mqprovider'
    desc 'Optional. The JMS Provider the Connection Factory should be using. Defaults to `builtin_mqprovider`'
  end

  newparam(:cf_type) do
    defaultto :CF
    newvalues(:CF, :QCF, :TCF)
    desc 'Optional. The Connection Factory type. Can be one of CF, QCF or TCF. Defaults to CF.'
    debug "CF Type: #{resource[:cf_type]}"
    debug "CF Type: #{self[:cf_type]}"
  end

  newproperty(:jndi_name) do
    desc 'Required. The JNDI Name the Connection Factory should be set to. Must be referenced only once per scope'
  end

  newproperty(:description) do
    desc 'Required. A meanigful description of the CF object.'
  end

  newproperty(:qmgr_data) do
    desc "A hash table containing the QMGR settings data to apply to the Connection Factory. See createWMQConnectionFactory() manual"

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

    # Whilst we can create a CF with not a lot of data, what's the point?
    # Bail out if the value passed is not a hash or if the hash is empty.
    # At the very least force the user to reflect for their choices in life.
    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: qmgr_data property must be a hash' unless value.kind_of?(Hash)
      raise Puppet::Error  'Puppet::Type::Websphere_Cf: qmgr_data property cannot be empty' if value.empty?
    end

    # Do some basic checking for the passed in QMGR params
    # Because of their number and complexity, there's only so much we can do before we let the users hurt themselves.
    munge do |value|
      munged_values={}
      value.each do |k, v|
        # camelCase and convert our hash keys to symbols.
        k_sym = k.split('_').inject{|m, p| m + p.capitalize}.to_sym

        case k_sym
        when :brokerCtrlQueue, :brokerSubQueue, :brokerCCSubQueue, :brokerVersion, :brokerPubQueue, :tempTopicPrefix, :pubAckWindow, :subStore, :stateRefreshInt, :cleanupLevel, :sparesSubs, :wildcardFormat, :brokerQmgr, :clonedSubs, :msgSelection
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type QCF" if self[:cf_type] == 'QCF'
        when :msgRetention, :rescanInterval, :tempQueuePrefix, :modelQueue, :replyWithRFH2
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type TCF" if self[:cf_type] == 'TCF'
        #else
        #  super
        end
        munged_values[k_sym] = v
      end
      munged_values
    end
  end

  newproperty(:mapping_data) do
    desc 'A hash containing the Auth mapping data'
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
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: mapping_data property must be a hash' unless value.kind_of?(Hash)
      #fail "Hash cannot be empty" if value.empty?
    end

    # camelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newproperty(:conn_pool_data) do
    desc 'A hash containing the Connection Pool settings'
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
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: conn_pool_data property must be a hash' unless value.kind_of?(Hash)
      #fail "Hash cannot be empty" if value.empty?
    end

    # CamelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newproperty(:sess_pool_data) do
    desc 'A hash containing the Session Pool settings'
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
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: sess_pool_data property must be a hash' unless value.kind_of?(Hash)
      #fail "Hash cannot be empty" if value.empty?
    end

    # CamelCase and convert our hash keys to symbols.
    munge do |value|
      munged_values = value.map{|k, v| [k.split('_').inject{|m, p| m + p.capitalize}.to_sym, v]}.to_h
    end
  end

  newparam(:sanitize) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional. Whether basic sanitation will be applied to the encountered resourceProperties. See `ignored_names`. Defaults to `true`'
  end

  newparam(:ignored_names, array_matching: :all) do
    defaultto ['zip','xml']
    desc <<-EOT 
    Optional. An array of name suffixes for objects which were found stored as resourceProperties and severely impeding the performance of
    Connection Factory resource discovery.
    
    If listed and the `sanitize` attribute is set to `true`, any resourceProperty containing any of them in its name will be ignored.

    Defaults to: ['zip','xml']
    Example: ignored_names => ['zip','xml']
    Will ignore resourceProperties like:

    <resourceProperties xmi:id="J2EEResourceProperty_1499488858500" name="widgetFeedUrlMap.xml" value="&lt;?xml version=&quot;..." ...>
    <resourceProperties xmi:id="J2EEResourceProperty_1499488861016" name="SolutionAdministration.zip" value="UEsDBAoAAAAIABIaa..." ...>
    EOT
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the Queue Connection Factory.
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Connection Factory should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Connection Factory should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Connection Factory should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Connection Factory should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Connection Factory should be set under.  Basically, where
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
