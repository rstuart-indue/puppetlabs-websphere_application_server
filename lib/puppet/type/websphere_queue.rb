# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_queue) do
  @doc = <<-DOC
    @summary This manages a WebSphere JMS Queue resource.

    @example
      websphere_queue { 'was_q':
        ensure          => 'present',
        jms_provider    => 'builtin_mqprovider',
        description     => 'Websphere Queue',
        jndi_name       => 'jms/PUPQ',
        queue_name      => 'SOME.PUPQUEUE.NAME',
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
      # QName
      [
        %r{^([^:]+)$},
        [
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:QName
      [
        %r{^(.*):(.*)$},
        [
          [:profile_base],
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:QName
      [
        %r{^(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:QName
      [
        %r{^(.*):(.*):(cell):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:QName
      [
        %r{^(.*):(.*):(cluster):(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:QName
      [
        %r{^(.*):(.*):(node):(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:q_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:QName
      [
        %r{^(.*):(.*):(server):(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:q_name],
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

    [:q_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:q_name) do
    isnamevar
    desc <<-EOT
    Required. The administrative name assigned to this WebSphere MQ messaging provider queue type destination to create/modify/remove.
    
    Example: `QCFEvents`
    EOT
  end

  newparam(:jms_provider) do
    defaultto 'builtin_mqprovider'
    desc 'Optional. The JMS Provider the Queue should be using. Defaults to `builtin_mqprovider`'
  end

  newproperty(:queue_name) do
    desc 'Required. The name of the WebSphere MQ queue to use to store messages for the WebSphere MQ messaging provider queue type destination definition.'
  end

  newproperty(:jndi_name) do
    desc 'Required. The name used to bind this object into WebSphere Application Server JNDI. Must be referenced only once per scope'
  end

  newproperty(:description) do
    desc 'Required. A meanigful description of the Queue object.'
  end

  newproperty(:qmgr) do
    desc 'Optional. The queue manager that hosts the WebSphere MQ queue.'
  end

  newproperty(:persistence) do
    defaultto :APP
    newvalues(:APP, :QDEF, :PERS, :NON, :HIGH)
    desc 'Optional. This parameter determines the level of persistence used to store messages sent to this destination.'
  end

  newproperty(:priority) do
    defaultto :APP
    newvalues(:APP, :QDEF, 0..9)
    desc 'Optional. The priority level to assign to messages sent to this destination.'
  end

  newproperty(:expiry) do
    defaultto :APP
    newvalues(:APP, :UNLIM, 0..Integer::INFINITY)
    desc 'Optional. The length of time after which messages sent to this destination expire and are dealt with according to their disposition options.'
  end

  newproperty(:ccsid) do
    defaultto 1208

    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_queue: ccsid property must be an integer' unless value.kind_of?(Integer)
      raise Puppet::Error  'Puppet::Type::Websphere_queue: ccsid property cannot be negative' if value < 0
    end
    desc 'Optional. The coded character set identifier (CCSID).'
  end

  newproperty(:native_encoding) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional.This parameter specifies whether to use native encoding or not. It can take a value true or false. If true, the values of the integer_encoding, decimal_encoding and fp_encoding attributes are ignored'
  end

  newproperty(:integer_encoding) do
    defaultto :Normal
    newvalues(:Normal, :Reversed)
    desc 'Optional. The integer encoding setting for this queue.'
  end

  newproperty(:decimal_encoding) do
    defaultto :Normal
    newvalues(:Normal, :Reversed)
    desc 'Optional. The decimal encoding setting for this queue.'
  end

  newproperty(:fp_encoding) do
    defaultto :IEEENormal
    newvalues(:IEEENormal, :IEEEReversed, :'z/OS')
    desc 'Optional. The floating point encoding setting for this queue.'
  end

  newproperty(:use_rfh2) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional. This parameter determines whether an RFH version 2 header is appended to messages sent to this destination, also know as targetClient'
  end

  newproperty(:send_async) do
    defaultto :QDEF
    newvalues(:YES, :NO, :QDEF)
    desc 'Optional. This parameter determines whether messages can be sent to this destination without queue manager acknowledging that they have arrived.'
  end

  newproperty(:read_ahead) do
    defaultto :QDEF
    newvalues(:YES, :NO, :QDEF)
    desc 'Optional. This parameter determines whether messages for non-persistent consumers can be read ahead and cached.'
  end

  newproperty(:read_ahead_close) do
    defaultto :DELIVERALL
    newvalues(:DELIVERALL, :DELIVERCURRENT)
    desc 'Optional. This parameter specifies the read ahead close method for the message consumer.'
  end

  # ------------------------------------
  newproperty(:q_data) do
    default_q_data = { 
      :persistence => '',
      :priority => '',
      :expiry => '',
      :ccsid => '',
      :use_native_encoding => '',
      :integer_encoding => '',
      :decimal_encoding => '',
      :floating_point_encoding => '',
      :use_RFH2 => '',
      :send_async => '',
      :read_ahead => '',
      :read_ahead_close => 'DELIVERALL'
    }
    defaultto default_mapping_data 
    desc "A hash table containing the Queue settings data to apply to the Queue resource. See createWMQQueue() manual"

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
      raise Puppet::Error, 'Puppet::Type::Websphere_queue: qmgr_data property must be a hash' unless value.kind_of?(Hash)
      #raise Puppet::Error  'Puppet::Type::Websphere_queue: qmgr_data property cannot be empty' if value.empty?
    end

    # Do some basic checking for the passed in Q params
    # Because of their number and complexity, there's only so much we can do before we let the users hurt themselves.
    munge do |value|
      munged_values={}
      value.each do |k, v|
        # camelCase and convert our hash keys to symbols.
        k_sym = k.split('_').inject{|m, p| m + p.capitalize}.to_sym

        case k_sym
        when :brokerCtrlQueue, :brokerSubQueue, :brokerCCSubQueue, :brokerVersion, :brokerPubQueue, :tempTopicPrefix, :pubAckWindow, :subStore, :stateRefreshInt, :cleanupLevel, :sparesSubs, :wildcardFormat, :brokerQmgr, :clonedSubs, :msgSelection
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type QCF" if resource[:cf_type] == :QCF
        when :msgRetention, :rescanInterval, :tempQueuePrefix, :modelQueue, :replyWithRFH2
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type TCF" if resource[:cf_type] == :TCF
        end
        munged_values[k_sym] = v
      end
      munged_values
    end
  end
  # ------------------------------------

  newproperty(:custom_properties) do
    desc "A hash table containing the custom properties to be passed to the WebSphere MQ messaging provider queue type destination implementation. See createWMQQueue() manual"

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

    # Passed argument must be a hash
    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_Queue: custom_properties property must be a hash' unless value.kind_of?(Hash)
    end

    # Do some basic checking for the passed in custom properties params
    # Because of their number and complexity, there's only so much we can do before we let the users hurt themselves.
    munge do |value|
      munged_values={}
      value.each do |k, v|
        # camelCase and convert our hash keys to symbols. Not sure we need this.
        #k_sym = k.split('_').inject{|m, p| m + p.capitalize}.to_sym

        munged_values[k.to_sym] = v
      end
      munged_values
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
    Queue resource discovery.
    
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
    The scope for the Queue.
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Queue should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Queue should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Queue should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Queue should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Queue should be set under.  Basically, where
    are we finding `wsadmin`

    This is synonymous with the 'profile' parameter.

    Example: dmgrProfile01"
    EOT
  end

  newparam(:profile_base) do
    isnamevar
    desc "The base directory where profiles are stored. Example: /opt/IBM/WebSphere/AppServer/profiles"
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
