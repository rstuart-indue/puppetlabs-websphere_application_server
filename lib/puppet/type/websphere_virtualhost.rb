# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_virtualhost) do
  @doc = <<-DOC
    @summary This manages a WebSphere Virtual Host resource.

    @example
      websphere_virtualhost { 'virtual_host_name':
        ensure            => 'present',
        alias_list        => [['*', 9998], ['host', 'port']]
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
      # VHost
      [
        %r{^([^:]+)$},
        [
          [:vhost],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:VHost
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:vhost],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:VHost
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:vhost],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:VHost
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:vhost],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be cell" unless %r{^(cell)$}.match?(self[:scope])
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:vhost, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:vhost) do
    isnamevar
    desc <<-EOT
    Required. The Virtual Host alias name to create/modify/remove.
    
    Example: `puppet_vhost`
    EOT
  end

  newproperty(:alias_list, array_matching: :all) do
    defaultto [[]]
    desc 'Optional. A list of host_name - port pairs to be used as aliases for the defined Virtual Host. Defaults to an empty list'
    # Override insync? to make sure we're comparing sorted arrays
    def insync?(is)
      is.sort == should.sort
    end
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the Virtual Host .
    Valid value: cell
    EOT
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Virtual Host should be set'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Virtual Host should be set under.  Basically, where
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