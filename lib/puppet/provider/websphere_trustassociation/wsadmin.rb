# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_trustassociation).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a Trust Association for a specific security Domain.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-configuring-trust-association-using
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-securityconfigurationcommands-command-group-admintask-object

    This provider relies on the AdminTask sub-commands for managing Trust Associations for a given security domain.
    If the TA does not exist, it will be automatically created and the Global TA interceptors will be copied in as
    defaults.

    This provider operates only for LTPA Authentication which is set up at the Sec Domain level.
    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize(val = {})
    super(val)
    @property_flush = {}
    @tai_state = ''

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  # This type only operatest at cell level.
  # for 'global' security domain:
  # /opt/ibm/WebSphere/AppServer/profiles/PROFILE_DMGR_01/config/cells/CELL_01/security.xml
  # for a custom security domain:
  # /opt/ibm/WebSphere/AppServer/profiles/PROFILE_DMGR_01/config/waspolicies/default/securitydomains/SEC_DOM_01/domain-security.xml
  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    case resource[:secd_name]
    when 'global'
      query = "/Cell:#{resource[:cell]}"
      mod   = "cells/#{resource[:cell]}"
      file += "/config/cells/#{resource[:cell]}/security.xml"
    else
      # TODO: this may need some tuning - but cannot test it because we're not using this kind of config.
      query = "/Securitydomains:#{resource[:secd_name]}"
      mod   = "securitydomains/#{resource[:secd_name]}"
      file += "/config/waspolicies/default/securitydomains//#{resource[:secd_name]}/domain-security.xml"
    end

    case what
    when 'query'
      query
    when 'mod'
      mod
    when 'file'
      file
    else
      debug 'Invalid scope request'
    end
  end

  # Create a Trust Association
  # TODO: this may need some attention in the future - when dealing with non-global security domains.
  #       It appears the Trust Association is created, but it needs to be switched from "use global"
  #       to it.
  def create

    # Only set the sec_domain_str to something if we're not working on the global domain.
    case resource[:secd_name]
    when 'global'
      sec_domain_str = ''
    else 
      sec_domain_str = "'#{resource[:secd_name]}'"
    end

    enabled_str = resource[:enabled].to_s

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association creation
sec_domain = '#{sec_domain_str}'
enabled_state = '#{enabled_str}'

msgPrefix = 'WASTrustAssociation create:'

try:
  if sec_domain:
    AdminTask.configureTrustAssociation((['-securityDomainName', sec_domain, '-enable', enabled_state]))
    AdminUtilities.debugNotice("Created Trust Association enabled state to " + enabled_state + " for security domain " + sec_domain)
  else:
    AdminTask.configureTrustAssociation((['-enable', enabled_state]))
    AdminUtilities.debugNotice("Created Trust Association enabled state to " + enabled_state + " for the global security domain ")
  #endIf

  AdminConfig.save()
except:
  typ, val, tb = sys.exc_info()
  if (typ==SystemExit):  raise SystemExit,`val`
  if (failonerror != AdminUtilities._TRUE_):
    print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
    val = "%s %s" % (sys.exc_type, sys.exc_value)
    raise Exception("ScriptLibraryException: " + val)
  else:
    AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
  #endIf
#endTry
END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Activation Specs: #{resource[:as_name]} of type #{resource[:destination_type]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Trust Association exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:secd_name]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    case resource[:secd_name]
    when 'global'
      # Out of the box - this is the ID of the global security auth mechanism.
      # If this has changed, the whole planet is on a cob.
      auth_mechanism = XPath.first(doc, "/security:Security[@activeAuthMechanism='LTPA_1']/authMechanisms[@xmi:type='security:LTPA'][@xmi:id='LTPA_1']")
    else
      auth_mechanism = XPath.first(doc, "/security:AppSecurity/authMechanisms[@xmi:type='security:LTPA']")
    end

    tai_entry = XPath.first(auth_mechanism, 'trustAssociation') unless auth_mechanism.nil?
    @tai_state = XPath.first(tai_entry, "@*[local-name()='enabled']").value.to_sym unless tai_entry.nil?

    debug "Discovered Trust Association for: #{resource[:secd_name]} with state: #{@tai_state.to_s}"

    # And now, close the deal, say whether the Trust Association exists or not.
    !tai_entry.nil?
  end

  # Get the enabled state of the Trust Association
  def enabled
    return @tai_state
  end

  # Set the enabled state of the Trust Association
  def enabled=(val)
    @property_flush[:enabled] = val
  end

  # Remove Trust Association - if not the global security domain
  def destroy

    if (resource[:secd_name] == 'global')
      raise Puppet::Error, 'Refusing to destroy the built-in Trust Association for the Global Security domain. Please set `enabled => false` instead.'
    end

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association destruction
sec_domain = '#{resource[:secd_name]}'

msgPrefix = 'WASTrustAssociation destroy:'

try:
  # Remove the trust association object from the specified security domain
  AdminTask.unconfigureTrustAssociation(['-securityDomainName', sec_domain])
  AdminUtilities.debugNotice("Removed Trust Association for security domain: " + str(sec_domain))

  AdminConfig.save()
except:
  typ, val, tb = sys.exc_info()
  if (typ==SystemExit):  raise SystemExit,`val`
  if (failonerror != AdminUtilities._TRUE_):
    print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
    val = "%s %s" % (sys.exc_type, sys.exc_value)
    raise Exception("ScriptLibraryException: " + val)
  else:
    AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
  #endIf
#endTry

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?
    sec_domain_str = ''
    if (resource[:secd_name] != 'global')
      sec_domain_str = "'#{resource[:secd_name]}'"
    end

    enabled_str = resource[:enabled].to_s

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association update
sec_domain = '#{sec_domain_str}'
enabled_state = '#{enabled_str}'

msgPrefix = 'WASTrustAssociation modify:'

try:
  if sec_domain:
    AdminTask.configureTrustAssociation((['-securityDomainName', sec_domain, '-enable', enabled_state]))
    AdminUtilities.debugNotice("Modified Trust Association enabled state to " + enabled_state + " for security domain " + sec_domain)
  else:
    AdminTask.configureTrustAssociation((['-enable', enabled_state]))
    AdminUtilities.debugNotice("Modified Trust Association enabled state to " + enabled_state + " for the global security domain ")
  #endIf

  AdminConfig.save()
except:
  typ, val, tb = sys.exc_info()
  if (typ==SystemExit):  raise SystemExit,`val`
  if (failonerror != AdminUtilities._TRUE_):
    print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
    val = "%s %s" % (sys.exc_type, sys.exc_value)
    raise Exception("ScriptLibraryException: " + val)
  else:
    AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
  #endIf
#endTry
END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
