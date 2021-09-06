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
        %r{^(.*):(.*)$},
        [
          [:profile_base],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CFName
      [
        %r{^(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cf_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:CFName
      [
        %r{^(.*):(.*):(cell):(.*):(.*)$},
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
        %r{^(.*):(.*):(cluster):(.*):(.*):(.*)$},
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
        %r{^(.*):(.*):(node):(.*):(.*):(.*)$},
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
        %r{^(.*):(.*):(server):(.*):(.*):(.*)$},
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
    raise ArgumentError, 'node is required when scope is server, cell, or node' if self[:node_name].nil? && self[:scope] =~ %r{(server|cell|node)}
    raise ArgumentError, 'cluster is required when scope is cluster' if self[:cluster].nil? && self[:scope] =~ %r{^cluster$}
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:cf_name, :server, :cell, :node, :cluster, :profile, :user].each do |value|
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

  newproperty(:cf_type) do
    defaultto :CF
    newvalues(:CF, :QCF, :TCF)
    desc 'Optional. The Connection Factory type. Can be one of CF, QCF or TCF. Defaults to CF.'
  end

  newproperty(:jndi_name) do
    desc 'Required. The JNDI Name the Connection Factory should be set to. Must be referenced only once per scope'
  end

  newproperty(:jms_provider) do
    defaultto 'builtin_mqprovider'
    desc 'Optional. The JMS Provider the Connection Factory should be using. Defaults to `builtin_mqprovider`'
  end

  # These are the things we need to keep track of
  # and manage if they need to set/reset
  newproperty(:description) do
    desc 'Required. A meanigful description of the CF object.'
  end

  newproperty(:qmgr_data, array_matching: :all) do
    desc "A hash table containing the QMGR settings data to apply to the Connection Factory. See createWMQConnectionFactory() manual"

    def insync?(is)
      # There will almost always be more properties on the system than
      # defined in the resource. Make sure the properties in the resource
      # are insync
      should.each_pair do |prop,value|
        return false unless is.key?(prop)
        # Stop after the first out of sync property
        return false unless property_matches?(is[prop],value)
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
      value.each do |k, v|
        case k
        when :brokerCtrlQueue, :brokerSubQueue, :brokerCCSubQueue, :brokerVersion, :brokerPubQueue, :tempTopicPrefix, :pubAckWindow, :subStore, :stateRefreshInt, :cleanupLevel, :sparesSubs, :wildcardFormat, :brokerQmgr, :clonedSubs, :msgSelection
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type QCF" unless resource[:cf_type] != 'QCF'
        when :msgRetention, :rescanInterval, :tempQueuePrefix, :modelQueue, :replyWithRFH2
          raise Puppet::Error "Puppet::Type::Websphere_Cf: Argument error in qmgr_data: parameter #{k} with value #{v} is incompatible with type TCF" unless resource[:cf_type] != 'TCF'
        else
          super
        end
      end
    end
  end

  newproperty(:conn_pool_data, array_matching: :all) do
    desc 'A hash containing the Connection Pool settings'
    def insync?(is)
      # There will almost always be more properties on the system than
      # defined in the resource. Make sure the properties in the resource
      # are insync
      should.each_pair do |prop,value|
        return false unless is.key?(prop)
        # Stop after the first out of sync property
        return false unless property_matches?(is[prop],value)
      end
      true
    end

    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: conn_pool_data property must be a hash' unless value.kind_of?(Hash)
      #fail "Hash cannot be empty" if value.empty?
    end   
  end

  newproperty(:sess_pool_data, array_matching: :all) do
    desc 'A hash containing the Session Pool settings'
    def insync?(is)
      # There will almost always be more properties on the system than
      # defined in the resource. Make sure the properties in the resource
      # are insync
      should.each_pair do |prop,value|
        return false unless is.key?(prop)
        # Stop after the first out of sync property
        return false unless property_matches?(is[prop],value)
      end
      true
    end

    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_Cf: sess_pool_data property must be a hash' unless value.kind_of?(Hash)
      #fail "Hash cannot be empty" if value.empty?
    end  
  end

## Defaults for connection / session pools
reapTime          = '180'
connectionTimeout = '30'
unusedTimeout     = '300'
agedTimeout       = '0'
purgePolicy       = 'EntirePool'

pool_defaults_dict = {}
pool_defaults_dict['both_reapTime']           = reapTime
pool_defaults_dict['both_connectionTimeout']  = connectionTimeout
pool_defaults_dict['both_unusedTimeout']      = unusedTimeout
pool_defaults_dict['both_agedTimeout']        = agedTimeout
pool_defaults_dict['both_purgePolicy']        = purgePolicy
pool_defaults_dict['cp_min_connections']      = '10'
pool_defaults_dict['cp_max_connections']      = '35'
pool_defaults_dict['sp_min_connections']      = '1'
pool_defaults_dict['sp_max_connections']      = '35'


## Queue Connection Factory Defaults
qcf_defaults_dict = {}
qcf_defaults_dict.update(pool_defaults_dict)
qcf_defaults_dict['qmgrName']                = queueMgr
qcf_defaults_dict['qmgrSvrconnChannel']      = srvConChannel
qcf_defaults_dict['sslType']                 = sslType
qcf_defaults_dict['sslConfiguration']        = sslAlias
qcf_defaults_dict['wmqTransportType']        = 'CLIENT'
qcf_defaults_dict['clientId']                = clientID
qcf_defaults_dict['ccsid']                   = '819'
qcf_defaults_dict['modelQueue']              = 'SYSTEM.DEFAULT.MODEL.QUEUE'
qcf_defaults_dict['connectionNameList']      = connectionNameList
qcf_defaults_dict['both_agedTimeout']        = '300'
qcf_defaults_dict['type']                    = 'QCF'
qcf_defaults_dict['mappingAlias']            = ''
qcf_defaults_dict['containerAuthAlias']      = ''
qcf_defaults_dict['componentAuthAlias']      = ''
qcf_defaults_dict['xaRecoveryAuthAlias']     = ''


qcf_dict = {}
qcf_dict['QCF'] =  {
  'jndiName'      : 'jms/QCF',
  'description'   : 'OPF QCF Queue Connection Factory',
  'cp_update_pool': 'True',
  'sp_update_pool': 'True'
}

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

  newparam(:node) do
    isnamevar
    desc 'The node for which this Connection Factory should be set in'
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
