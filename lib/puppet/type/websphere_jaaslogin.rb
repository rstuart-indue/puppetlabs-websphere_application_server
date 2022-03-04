# frozen_string_literal: true

require 'pathname'
require 'json'

Puppet::Type.newtype(:websphere_jaaslogin) do
  @doc = <<-DOC
    @summary This manages a WebSphere JAAS Login resource.

    @example
      websphere_jaaslogin { 'JAAS_LOGIN_CONFIG':
        ensure              => 'present',
        login_type          => 'system',
        login_modules       => $login_modules_hash
        profile_base        => '/opt/IBM/WebSphere/AppServer/profiles',
        dmgr_profile        => 'PROFILE_DMGR_01',
        cell                => 'CELL_01',
        user                => 'webadmin',
        wsadmin_user        => 'wasadmin',
        wsadmin_pass        => 'password',
      }

    Where the login modules hash is composed of:
    $login_modules_hash = {
      com.foo.bar.security.server.lm.wsMapDefaultInboundLoginModule => {
        ordinal                 => 1,
        authentication_strategy => 'REQUIRED',
        custom_properties       => ["Custom_PROP_NAME1=Custom_PROP_VALUE1","Custom_PROP_NAME2=Custom_PROP_VALUE2"]
      }
      com.baz.quux.security.server.lm.ltpaLoginModule => {
        ordinal                 => 2,
        authentication_strategy => 'SUFFICIENT',
      }
    }

    Note: The login modules hash is keyed on the list of login modules names which in turn are hashes which 
          specify the properties for each login module. The mandatory fields for a login module are `ordinal`
          and `authentication_strategy`. The 'ordinal' field describes the order in which the modules will be
          stacked for consulting, whereas the authentication_strategy specifies the behaviour of the module as
          the authentication process moves through the stack of login modules.

          The `custom_properties` field is an array containing string elements in the format of `"Key=Value".
          If `custom_properties` is not present, the type will not create/manage any custom properties for the
          given login module. If `custom_properties` is an empty array, this will cause the removal of all
          custom properties for the given login module.

          If the login_modules hash is not provided, the type will not manage the login modules. However,
          if it is provided, the type will bring the list of login modules in line with the provided configuration.
          If an empty hash `{}` is provided, then, all the login modules will be deleted out of the
          target JAAS login.

          To manage any default JAAS logins, you need to build the hash with all the existing login modules
          and their custom properties as described by the default installation.
  DOC

  ensurable

  # Our title_patterns method for mapping titles to namevars for supporting
  # composite namevars.
  def self.title_patterns
    [
      # JAASLogin
      [
        %r{^([^:]+)$},
        [
          [:jaas_login],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:JAASLogin
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:jaas_login],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:JAASLogin
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:jaas_login],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:cell:CELL_01:JAASLogin
      [
        %r{^([^:]+):([^:]+):(cell):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:scope],
          [:cell],
          [:jaas_login],
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

    [:jaas_login, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end 
  end

  newparam(:jaas_login) do
    isnamevar
    desc <<-EOT
    Required. The JAAS Login alias name to create/modify/remove.
    
    Example: `puppet_jaaslogin`
    EOT
  end

  newparam(:login_type) do
    defaultto :system
    newvalues(:system, :application)
    desc 'Optional. The type for the defined JAAS Login - it can only be `system` or `application`. Defaults to `system`'
  end

  newproperty(:login_modules) do
    desc <<-EOT
      Optional. A hash of login modules to be configured for the defined JAAS Login. Passing an empty hash `{}` will
      delete all and any pre-existing login modules for the target JAAS Login.
      
      Defaults to `nil`, which has the effect of keeping any manually configured login modules in the target JAAS Login.
    EOT

    # Passed argument must be a hash
    # TODO: Perhaps a validation of the provided login modules should happen here. Sadly, it's more wagging of the
    #       hash - back and forth through its keys and values.
    # Because of their number and complexity, there's only so much we can do before we let the users hurt themselves.
    validate do |value|
      raise Puppet::Error, 'Puppet::Type::Websphere_jaaslogin: login_modules property must be a hash' unless value.kind_of?(Hash)
    end

    # Turn our keys into symbols - yes we turn a hash into json and then back again, with the option of symbolizing the keys.
    munge do |value|
      munged_values = JSON.parse(value.to_json, { symbolize_names: true })
    end
  end

  newparam(:scope) do
    isnamevar
    desc <<-EOT
    The scope for the JAAS Login .
    Valid value: cell
    EOT
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this JAAS Login should be set'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this JAAS Login should be set under.  Basically, where
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