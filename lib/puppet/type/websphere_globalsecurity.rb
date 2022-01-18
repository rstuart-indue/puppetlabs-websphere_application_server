# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_globalsecurity) do
  @doc = <<-DOC
    @summary This manages a WebSphere Trust Association configuration.

    This module manages the Trust Association configuration for a given security domain.
    The security domain has to exist, or can be the default Global one.

    @example
      websphere_globalsecurity { 'global':
        ensure              => 'present',
        appsecurity         => true,
        profile_base        => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile        => 'PROFILE_DMGR_01',
        cell                => 'CELL_01',
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
      # SECDomainName
      [
        %r{^([^:]+)$},
        [
          [:secd_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:SECDomainName
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:secd_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:SECDomainName
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:secd_name],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CELL_01:SECDomainName
      [
        %r{^([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cell],
          [:secd_name],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'Security Domain name is required' if self[:secd_name].nil?
    raise ArgumentError, "Invalid Security Domain #{self[:secd_name]} - must be 'global'" unless %r{^global$}.match?(self[:secd_name])
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:secd_name) do
    isnamevar
    desc <<-EOT
    Required. The Security Domain name target for the global security settings.

    NOTE: The Security Domain has to be set to `global`.
    
    Example: `global`
    EOT
  end
  
  newproperty(:appsecurity) do
    defaultto :false
    newvalues(:true, :false)
    desc 'Optional. Sets whether Application Security is enabled. Defaults to false'

    # Override insync? to make sure we're comparing symbols
    def insync?(is)
      is.to_sym == should.to_sym
    end
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which the global security settings should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which the global security settings should be set under.  Basically, where
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