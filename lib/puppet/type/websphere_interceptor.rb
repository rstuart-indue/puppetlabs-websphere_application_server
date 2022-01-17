# frozen_string_literal: true

require 'pathname'

Puppet::Type.newtype(:websphere_interceptor) do
  @doc = <<-DOC
    @summary This manages a WebSphere Trust Association Interceptor configuration.

    This module manages a Trust Association Interceptor configuration for a given security domain.
    The security domain has to exist, or can be the default Global one.

    @example
      websphere_interceptor { 'global':
        ensure              => 'present',
        properties          => tai_properties,
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
      # interceptor_classname
      [
        %r{^([^:]+)$},
        [
          [:interceptor_classname],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:interceptor_classname
      [
        %r{^([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:interceptor_classname],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:interceptor_classname
      [
        %r{^([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:interceptor_classname],
        ],
      ],
      # /opt/IBM/WebSphere/AppServer/profiles:PROFILE_DMGR_01:CELL_01:SECDomainName:interceptor_classname
      [
        %r{^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$},
        [
          [:profile_base],
          [:dmgr_profile],
          [:cell],
          [:secd_name],
          [:interceptor_classname],
        ],
      ],
    ]
  end

  validate do
    raise ArgumentError, 'cell is required' if self[:cell].nil?
    raise ArgumentError, 'Interceptor Classname is required' if self[:interceptor_classname].nil?
    raise ArgumentError, "Invalid profile_base #{self[:profile_base]}" unless Pathname.new(self[:profile_base]).absolute?

    if self[:profile].nil?
      raise ArgumentError, 'profile is required' unless self[:dmgr_profile]
      self[:profile] = self[:dmgr_profile]
    end

    [:interceptor_classname, :secd_name, :cell, :profile, :user].each do |value|
      raise ArgumentError, "Invalid #{value} #{self[:value]}" unless %r{^[-0-9A-Za-z._]+$}.match?(value)
    end

    raise Puppet::Error, 'Puppet::Type::Websphere_Interceptor: when defined, `properties` property must be a hash' unless (self[:properties].nil? or self[:properties].kind_of?(Hash))
  end

  newparam(:interceptor_classname) do
    isnamevar
    desc <<-EOT
    Required. The Interceptor Class Name for the Trust Association Interceptor.
    
    Example: `com.ibm.ws.security.spnego.TrustAssociationInterceptorImpl`
    EOT
  end

  newparam(:secd_name) do
    isnamevar
    desc <<-EOT
    Required. The Security Domain name target for the Trust Association Interceptor.

    NOTE: The Security Domain has to exist prior to the Trust Association Interceptor operations. To operate on the
    "Global" Security Domain - use the "global" keyword.
    
    Example: `global`
    EOT
  end
  
  newproperty(:properties) do
    desc <<-EOT 
    Optional. A hash of Key-Value pairs which specifies the trust information for reverse proxy servers. 

    Example: ' {
                  'interceptedPath' => '/AppWS/Path.*',
                  'domainName'      => 'Domain',
                } '
    EOT

    # Compare the two hashes - the is{} and should{}. Bail out at the first failed comparison.
    def insync?(is)
      should.each_pair do |prop,value|
        return false unless property_matches?(is[prop],value)
      end
      true
    end
  end

  newparam(:cell) do
    isnamevar
    desc 'The cell for which this Trust Association Interceptor should be set in'
  end

  newparam(:profile) do
    desc "The profile to run 'wsadmin' under"
  end

  newparam(:dmgr_profile) do
    isnamevar
    defaultto { @resource[:profile] }
    desc <<-EOT
    The DMGR profile for which this Trust Association Interceptor should be set under.  Basically, where
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