# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_authalias) do
  @doc = <<-DOC
    @summary This manages a WebSphere authentication data entry for a
    J2EE Connector architecture (J2C) connector in the global security
    or security domain configuration.

    This implementation only manages the global security configuration

    @example
      websphere_auth_data_entry { 'j2c_alias':
        ensure          => 'present',
        alias           => 'j2c_alias',
        user            => 'jbloggs',
        password        => 'somePassword',
        manage_password => false,
        description     => 'J2C auth data entry alias for jbloggs',
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
      # alias
      [
        %r{^([^:]+)$},
        [
          [:alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:alias
      [
        %r{^(.*):(.*)$},
        [
          [:profile_base],
          [:alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:alias
      [
        %r{^(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:alias],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CELL_01:alias
      [
        %r{^(.*):(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cell],
          [:alias],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, 'profile_base is required' if self[:profile_base].nil?
    raise ArgumentError, 'dmgr_profile is required' if self[:dmgr_profile].nil?
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:alias, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:alias) do
    isnamevar
    desc <<-EOT
    Required. The J2C auth data entry alias to create/modify/remove.  For example,
    `j2c_alias`
    EOT
  end

  # These are the things we need to keep track of
  # and manage if they need to set/reset
  newproperty(:common_name) do
    desc 'The given name of the user.'
  end

  newproperty(:surname) do
    desc 'The surname of the user'
  end

  newproperty(:mail) do
    desc 'The e-mail address of user'
  end

  newproperty(:password) do
    desc 'The password associated with the user'
  end

  newparam(:manage_password) do
    defaultto :false
    newvalues(:true, :false)
    desc <<-EOT
    Defines whether ongoing password management is done by puppet. By default
    it is set to 'false'

    Example: manage_password => false,
    EOT
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell name where this user should be created in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The dmgr profile in which this user should be created. It is where
    the `wsadmin` command can be found

    This is synonimous with the 'profile' parameter.

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
    desc "The user to run 'wsadmin' as. Default is 'root'"
  end

  newparam(:wsadmin_user) do
    desc 'The username for wsadmin authentication - required if security is enabled'
  end

  newparam(:wsadmin_pass) do
    desc 'The password for wsadmin authentication - required if security is enabled'
  end
end
