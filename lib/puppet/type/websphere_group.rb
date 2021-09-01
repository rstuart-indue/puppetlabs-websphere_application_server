# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_group) do
  @doc = <<-DOC
    @summary This manages a WebSphere group in the default WIM file based realm

    @example
      websphere_group { 'was_group':
        ensure          => 'present',
        description     => 'Websphere Internal Group',
        members         => ['jbloggs', 'foo', 'bar', 'baz'],
        enforce_members => true
        roles           => ['administrator','operator','configurator','monitor','deployer','adminsecuritymanager','nobody','iscadmins']
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
      # groupID
      [
        %r{^([^:]+)$},
        [
          [:groupid],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:groupID
      [
        %r{^(.*):(.*)$},
        [
          [:profile_base],
          [:groupid],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:groupID
      [
        %r{^(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:groupid],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CELL_01:groupID
      [
        %r{^(.*):(.*):(.*):(.*)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cell],
          [:groupid],
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

    [:groupid, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end
  end

  newparam(:groupid) do
    isnamevar
    desc <<-EOT
    Required. The name of the group to create/modify/remove.  For example,
    `was_group`
    EOT
  end

  # These are the things we need to keep track of
  # and manage if they need to set/reset
  newproperty(:description) do
    desc 'The description of the group.'
  end

  newproperty(:members, array_matching: :all) do
    defaultto []
    desc 'An optional list of members to be added to the group'

    # Ensure the arrays are sorted when we compare them:
    def insync?(is)
      is.sort == should.sort
    end
  end

  newparam(:enforce_members) do
    defaultto :true
    newvalues(:true, :false)

    desc <<-EOT
    An optional setting for group membership management. Defaults to 'true'
    which means that any group members found to be added via non-Puppet
    means will be removed, and only users listed in the 'members' property
    will be added to the group.

    Example: enforce_members => true
    EOT
  end

  newproperty(:roles, array_matching: :all) do
    defaultto []
    newvalues(
      :administrator,
      :operator,
      :configurator,
      :monitor,
      :deployer,
      :adminsecuritymanager,
      :nobody,
      :iscadmins
    )
    desc 'An optional list of roles this group will be assigned to'

    # Ensure the arrays are sorted when we compare them:
    def insync?(is)
      is.sort == should.sort
    end
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell name where this group should be created in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The dmgr profile in which this group should be created. It is where
    the `wsadmin` command can be found

    This is synonymous with the 'profile' parameter.

    Example: dmgrProfile01"
    EOT
  end

  newparam(:profile_base) do
    isnamevar
    desc <<-EOT
    The base directory where profiles are stored.

    Example: /opt/IBM/WebSphere/AppServer/profiles
    EOT
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
