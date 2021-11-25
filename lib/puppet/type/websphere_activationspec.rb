# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_activationspec) do
  @doc = <<-DOC
    @summary This manages a WebSphere JMS Activation Spec resource.

    @example
      websphere_activationspec { 'was_qas':
        ensure           => 'present',
        description      => 'Websphere Queue Activation Spec',
        jndi_name        => 'eis/QAS',
        destination_type => 'javax.jms.Queue',
        destination_jndi => 'jms/PUPQ',
        qmgr_data        => q_hash,
        sess_pool_data   => session_pool_hash,
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
      # ASName
      [
        %r{^([^:]+)$},
        [
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:ASName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:ASName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:ASName
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:ASName
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:ASName
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:as_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:ASName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:as_name],
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

    [:as_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end

    # Whilst we can create a AS with not a lot of data, what's the point?
    # Bail out if the value passed is not a hash or if the hash is empty.
    # At the very least force the user to reflect for their choices in life.
    raise Puppet::Error, 'Puppet::Type::Websphere_Activationspec: qmgr_data property must be a hash' unless self[:qmgr_data].kind_of?(Hash)
    raise Puppet::Error, 'Puppet::Type::Websphere_Activationspec: qmgr_data property cannot be empty' if self[:qmgr_data].empty?

    # We are looking for simultaneous use of the ccdt* options AND (qmgr* OR local*) options.
    # This regexp is a little complicated and involves look-ahead with no consumption of the 
    # matched pattern and if a match is found, then a secondary lookup is made for the incompatible
    # options. This will do a bare-minimum check of the validity of options passed to the
    # type, but it won't go very much further.
    #
    # See Websphere manual for the ActivationSpecs set of commands.
    qmgr_args = self[:qmgr_data].keys.to_s
    incompatible_args = /(?=.*:(ccdt\w+))(?(1).*:((qmgr|local)\w+))/.match(qmgr_args)
    raise Puppet::Error, "Puppet::Type::Websphere_Activationspec: qmgr_data #{incompatible_args[1]} is incompatible with #{incompatible_args[2]}" unless incompatible_args.nil?
    
  end

  newparam(:as_name) do
    isnamevar
    desc <<-EOT
    Required. The Activation Spec name to create/modify/remove.
    
    Example: `QASEvents`
    EOT
  end

  newparam(:jms_provider) do
    defaultto 'builtin_mqprovider'
    desc <<-EOT
    Optional. The JMS Provider the Activation Spec should be using. Defaults to `builtin_mqprovider`
    
    WARNING: It is unlikely a different JMS provider will work straight out of the box. 
             Even the default JMS provider is different enough, so support for changing the
             JMS provider is not implemented yet.

    Example: `builtin_mqprovider`
    EOT

  end

  newproperty(:description) do
    desc 'Required. A meanigful description of the AS object.'
  end

  newproperty(:jndi_name) do
    desc 'Required. The JNDI Name the Activation Spec should be set to. Must be referenced only once per scope'
  end

  newparam(:destination_type) do
    newvalues(:'javax.jms.Queue', :'javax.jms.Topic')
    desc 'Required. The Activation Spec destination type. Can be one of "javax.jms.Queue" or "javax.jms.Topic".'
  end

  newparam(:destination_jndi) do
    desc 'Required. The JNDI name of an IBM MQ messaging provider queue or topic type destination. When an MDB is deployed with this activation specification, messages for the MDB are consumed from this destination.'
  end

  newproperty(:qmgr_data) do
    desc "Required. A hash table containing the QMGR settings data to apply to the Activation Spec. See createWMQActivationSpec() manual"

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

    # Do some basic checking for the passed in QMGR params
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

  newparam(:sanitize) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional. Whether basic sanitation will be applied to the encountered resourceProperties. See `ignored_names`. Defaults to `true`'
  end

  newparam(:ignored_names, array_matching: :all) do
    defaultto ['zip','xml']
    desc <<-EOT 
    Optional. An array of name suffixes for objects which were found stored as resourceProperties and severely impeding the performance of
    Activation Spec resource discovery.
    
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
    The scope for the Activation Spec.
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this Activation Spec should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Activation Spec should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this Activation Spec should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this Activation Spec should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Activation Spec should be set under.  Basically, where
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