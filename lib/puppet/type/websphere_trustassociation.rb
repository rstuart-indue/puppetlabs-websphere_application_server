# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_trustassociation) do
  @doc = <<-DOC
    @summary This manages a WebSphere JVM Trust Association configuration.

    This module manages the Trust Association configuration for a given security domain.
    The security domain has to exist, or can be the default Global one.

    @example
      websphere_trustassociation { 'global':
        ensure              => 'present',
        enabled             => true,
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
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:SECDomainName
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
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:secd_name, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:secd_name) do
    isnamevar
    desc <<-EOT
    Required. The Security Domain name target for the Trust Association.

    NOTE: The Security Domain has to exist prior to the Trust Association operations. To operate on the
    "Global" Security Domain - use the "global" title.
    
    Example: `global`
    EOT
  end
  
  newproperty(:enabled) do
    defaultto :true
    newvalues(:true, :false)
    desc 'Optional. Sets whether Trust Association is enabled for the given Security Domain name. Defaults to true'
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this JVM Class Loader should be set in'
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