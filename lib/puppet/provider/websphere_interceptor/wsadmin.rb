# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_interceptor).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a Trust Association Interceptor for a specific security Domain.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-configuring-trust-association-using
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-securityconfigurationcommands-command-group-admintask-object

    This provider relies on the AdminTask sub-commands for managing Trust Association Interceptors for a given security domain.

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
    @old_tai = {}

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

  # Create a Trust Association Interceptor
  def create

    # Only set the sec_domain_str to something if we're not working on the global domain.
    case resource[:secd_name]
    when 'global'
      sec_domain_str = ''
    else 
      sec_domain_str = "'#{resource[:secd_name]}'"
    end

    interceptor_str = resource[:interceptor_classname].to_s

    # Convert this to a dumb string (square brackets and all) to pass to Jython
    custom_props_str = resource[:properties].map{|k,v| "#{k}=#{v}"}.to_s

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association Interceptor update
sec_domain = '#{sec_domain_str}'
interceptor_id = '#{interceptor_str}'
custom_props = '#{custom_props_str}'


msgPrefix = 'WASInterceptor create:'

try:
  if sec_domain:
    AdminTask.configureInterceptor(['-interceptor', interceptor_id, '-securityDomainName', sec_domain, '-customProperties', custom_props ])
    AdminUtilities.debugNotice("Created Trust Association Interceptor with custom props" + custom_props + " for security domain " + sec_domain)
  else:
    AdminTask.configureInterceptor(['-interceptor', interceptor_id, '-customProperties', custom_props ])
    AdminUtilities.debugNotice("Created Trust Association Interceptor with custom props " + custom_props + " for the global security domain ")
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
      Could not create Interceptor: #{resource[:interceptor_id]}}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Trust Association Interceptor exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of interceptor #{resource[:interceptor_classname]} for the #{resource[:secd_name]} security domain from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    case resource[:secd_name]
    when 'global'
      # Out of the box - this is the ID of the global security auth mechanism.
      # If this has changed, the whole planet is on a cob.
      auth_mechanism = XPath.first(doc, "/security:Security[@activeAuthMechanism='LTPA_1']/authMechanisms[@xmi:type='security:LTPA'][@xmi:id='LTPA_1']")
    else
      auth_mechanism = XPath.first(doc, "/security:AppSecurity/authMechanisms[@xmi:type='security:LTPA']")
    end

    # This may be a bit of a problem for custom security domains.
    tai_entry = XPath.first(auth_mechanism, "trustAssociation/interceptors[@interceptorClassName='#{resource[:interceptor_classname]}']") unless auth_mechanism.nil?

    XPath.each(tai_entry, "trustProperties") { |trust_property|
      prop_name, prop_value = XPath.match(trust_property, "@*[local-name()='name' or local-name()='value']")
      prop_name_str = prop_name.value.to_s
      prop_value_str = prop_value.value.to_s

      debug "Discovered Trust Association Interceptor property: #{prop_name_str} with value: #{prop_value_str}"
      @old_tai[prop_name_str] = prop_value_str

    } unless tai_entry.nil?

    # And now, close the deal, say whether the Trust Association Interceptor exists or not.
    !tai_entry.nil?
  end

  # Get TAI properties for a given Interceptor
  def properties
    return @old_tai
  end

  # Set TAI properties for a given Interceptor
  def properties=(val)
    @property_flush[:properties] = val
  end

  # Remove Trust Association Interceptor - even the ones in the global security domain
  def destroy
    # Only set the sec_domain_str to something if we're not working on the global domain.
    case resource[:secd_name]
    when 'global'
      sec_domain_str = ''
    else 
      sec_domain_str = "'#{resource[:secd_name]}'"
    end

    interceptor_str = resource[:interceptor_classname].to_s

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association Interceptor destruction
sec_domain = '#{sec_domain_str}'
interceptor_id = '#{interceptor_str}'


msgPrefix = 'WASInterceptor destroy:'

try:
  # Remove the trust association interceptor object from the specified security domain
  if sec_domain:
    AdminTask.unconfigureInterceptor(['-interceptor', interceptor_id, '-securityDomainName', sec_domain ])
    AdminUtilities.debugNotice("Removed Trust Association Interceptor ID" + interceptor_id + " for security domain " + sec_domain)
  else:
    AdminTask.unconfigureInterceptor(['-interceptor', interceptor_id ])
    AdminUtilities.debugNotice("Removed Trust Association Interceptor ID" + interceptor_id + " for the global security domain ")
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
    debug result
  end

  # This applies a new set of "custom properties" to the existing interceptor. There doesn't seem
  # to be a way to remove some and not others.
  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?
    # Only set the sec_domain_str to something if we're not working on the global domain.
    case resource[:secd_name]
    when 'global'
      sec_domain_str = ''
    else 
      sec_domain_str = "'#{resource[:secd_name]}'"
    end

    interceptor_str = resource[:interceptor_classname].to_s

    # Convert this to a dumb string (square brackets and all) to pass to Jython
    custom_props_str = resource[:properties].map{|k,v| "#{k}=#{v}"}.to_s


    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Trust Association Interceptor update
sec_domain = '#{sec_domain_str}'
interceptor_id = '#{interceptor_str}'
custom_props = '#{custom_props_str}'

msgPrefix = 'WASInterceptor modify:'

try:
  if sec_domain:
    AdminTask.configureInterceptor(['-interceptor', interceptor_id, '-securityDomainName', sec_domain, '-customProperties', custom_props ])
    AdminUtilities.debugNotice("Created Trust Association Interceptor with custom props" + custom_props + " for security domain " + sec_domain)
  else:
    AdminTask.configureInterceptor(['-interceptor', interceptor_id, '-customProperties', custom_props ])
    AdminUtilities.debugNotice("Created Trust Association Interceptor with custom props " + custom_props + " for the global security domain ")
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
