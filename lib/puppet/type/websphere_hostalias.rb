# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_hostalias) do
  @doc = <<-DOC
    @summary This manages a WebSphere Virtual Host resource.

    @example
      websphere_hostalias { '*:8080':
        ensure            => 'present',
        virtual_host      => 'default_host',
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
      # Hostname
      [
        %r{^([^:]+)$},
        [
          [:hostname],
        ],
      ],
      # Hostname:PortNumber
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:hostname],
          [:portnumber],
        ],
      ],
      # VirtualHost:Hostname:PortNumber
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:virtual_host],
          [:hostname],
          [:portnumber],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:VirtualHost:Hostname:PortNumber
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:virtual_host],
          [:hostname],
          [:portnumber],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, "Invalid scope #{self[:scope]}: Must be cell" unless %r{^(cell)$}.match?(self[:scope])
    raise ArgumentError, 'Alias Hostname is required' if self[:hostname].nil?
    raise ArgumentError, 'Alias Port number is required' if self[:portnumber].nil?
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:virtual_host, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:hostname) do
    isnamevar
    desc <<-EOT
    Required. The alias host name.
    
    Example: `www.my.website.com`
    EOT
  end

  newparam(:portnumber) do
    isnamevar
    desc <<-EOT
    Required. The alias port number.
    
    Example: `9443`
    EOT
  end

  newparam(:virtual_host) do
    isnamevar
    desc <<-EOT
    Required. The target Virtual Host.
    
    Example: `puppet_vhost`
    EOT
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