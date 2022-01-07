# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_jvm_classloader) do
  @doc = <<-DOC
    @summary This manages a WebSphere JVM Classloader property.

    This module attempts to manage a given classloader resource. However, this is not a straightforward process
    owing to the fact that class loaders are not "named resources" per se, which makes it difficult for Puppet
    to identify them once they were created. There is a degree of guess-work to find the right class-loader and
    if these are managed from an external source such as the WebUI, the process may backfire.

    The point is: you may need to choose whether to manage your class loaders with puppet, or, with other means.
    Or, just tread very carefully.

    In the grand scheme of things, class loaders do not change all the time, and they do reference shared libs
    by name, which allows shared libs to change their internal values independenty.

    @example
      websphere_jvm_classloader { 'PuppetClassloader':
        ensure              => 'present',
        mode                => 'PARENT_LAST',
        shared_libs         => ['APP_SRV_SHARED_LIBS', 'GLOBAL_SHARED_LIBS'],
        enforce_shared_libs => false,
        profile_base        => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile        => 'PROFILE_DMGR_01',
        cell                => 'CELL_01',
        cluster             => 'CLUSTER',
        node_name           => 'node',
        server              => 'app-server-name',
        user                => 'webadmin',
        wsadmin_user        => 'wasadmin',
        wsadmin_pass        => 'password',
      }
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # JCLName
      [
        %r{^([^:]+)$},
        [
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:JCLName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:JCLName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:JCLName
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cluster:CELL_01:TEST_CLUSTER_01:JCLName
      [
        %r{^([^:]+):([^:]+):(cluster):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:cluster],
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:node:CELL_01:AppNode01:JCLName
      [
        %r{^([^:]+):([^:]+):(node):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:jcl_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:server:CELL_01:AppNode01:AppServer01:JCLName
      [
        %r{^([^:]+):([^:]+):(server):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:node_name],
          [:server],
          [:jcl_name],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be cell, cluster, node, or server" unless %r{^(cell|cluster|node|server)$}.match?(self[:scope])
    raise ArgumentError, 'cluster is required when scope is cluster' if self[:cluster].nil? && self[:scope] =~ %r{^cluster$}
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'node_name is required' if self[:node_name].nil?
    raise ArgumentError, 'server is required' if self[:server].nil?
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:jcl_name, :server, :cell, :node_name, :cluster, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:jcl_name) do
    isnamevar
    desc <<-EOT
    Required. The JVM Class Loader name to create/modify/remove.
    
    Example: `AppServerXClassLoader`
    EOT
  end
  
  newproperty(:mode) do
    defaultto :PARENT_LAST
    newvalues(:PARENT_FIRST, :PARENT_LAST)
    desc 'Optional. The class loader delegation mode also known as the class loader order. Can only be PARENT_FIRST or PARENT_LAST. Defaults to PARENT_LAST'
  end

  newparam(:shared_libs, array_matching: :all) do
    desc <<-EOT
    Required. The list of Environment Shared Libraries to associate with this class loader.
    
    Example: `['APP_SRV_SHARED_LIBS', 'GLOBAL_SHARED_LIBS']`
    EOT

    # Ensure the arrays are sorted when we compare them:
    # TODO: There will almost always be more libraries on the system than
    # defined in the resource. Make sure the properties in the resource
    # are insync
    def insync?(is)
      is.sort == should.sort
    end
  end

  newparam(:enforce_shared_libs) do
    defaultto :false
    newvalues(:true, :false)

    desc <<-EOT
    An optional setting for Shared Library management. Defaults to 'false'
    which means that any shared libs references the class loader
    found to be added via non-Puppet means will be not be removed.

    Example: enforce_shared_libs => true
    EOT
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the JVM Class Loader.
    Valid values: cell, cluster, node, or server
    EOT
  end

  newparam(:server) do
    isnamevar
    desc 'The server for which this JVM Class Loader should be set in'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this JVM Class Loader should be set in'
  end

  newparam(:node_name) do
    isnamevar
    desc 'The node name for which this JVM Class Loader should be set in'
  end

  newparam(:cluster) do
    isnamevar
    desc 'The cluster for which this JVM Class Loader should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this JVM Class Loader should be set under.  Basically, where
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