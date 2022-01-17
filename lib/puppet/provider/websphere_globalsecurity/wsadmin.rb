# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_globalsecurity).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage security settings for the global security Domain.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-securityconfigurationcommands-command-group-admintask-object

    This provider relies on the AdminTask sub-commands for managing the global security options.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize(val = {})
    super(val)
    @property_flush = {}
    @old_sec = {}

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  # This type only operatest at cell level.
  # for 'global' security domain:
  # /opt/ibm/WebSphere/AppServer/profiles/PROFILE_DMGR_01/config/cells/CELL_01/security.xml
  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    case resource[:secd_name]
    when 'global'
      query = "/Cell:#{resource[:cell]}"
      mod   = "cells/#{resource[:cell]}"
      file += "/config/cells/#{resource[:cell]}/security.xml"
    else
      raise Puppet::Error, "Invalid security profile: #{resource[:secd_name]} - must be 'global'."
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

  # If we have to create the global security domain settings - something has gone awfully wrong.
  # Bail out hard and never look back.
  def create
    raise Puppet::Error, "Global Security Domain does not exist. Cowardly refusing to create it."
  end

  # Check to see if Global Securty Domain settings exist - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:secd_name]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    # Out of the box - this is the ID of the global security auth mechanism.
    # If this has changed, the whole planet is on a cob.
    sec_entry = XPath.first(doc, "/security:Security")

    XPath.each(sec_entry, "@*") {|attribute|
      @old_sec[attribute.name.to_s] = attribute.value.to_s
      debug "Discovered Global Securty Domain atribute name: #{attribute.name.to_s} with value: #{attribute.value.to_s}"
    } unless sec_entry.nil?

    # And now, close the deal, say whether the Global Securty Domain settings exists or not.
    !sec_entry.nil?
  end

  # Get the enabled state of the Global Securty Domain application security settings
  def appsecurity
    return @old_sec[:appEnabled]
  end

  # Set the enabled state of the Global Securty Domain application security settings
  def appsecurity=(val)
    @property_flush[:appEnabled] = val
  end

  # Prevent removal of the Global Securty Domain settings
  def destroy

    raise Puppet::Error, 'Refusing to destroy the default Global Security domain. You can only set properties on or off in it.'
    
  end

  # TODO: This can be expanded to accept many other params, but, since for our current purpose we don't
  #       need all the bells and whistles, the appsecurity param will do *just fine* TYVM.
  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    appsec_enable_str = resource[:appsecurity].to_s

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our Global Securty Domain settings update
app_enable = '#{appsec_enable_str}'

msgPrefix = 'WASGlobalSecurity Domain attributes modify:'

try:
  securityConfigID = AdminConfig.getid("/Security:/")

  # Set up the appEnabled state.
  AdminConfig.modify(securityConfigID, [['appEnabled', app_enable]])
  AdminUtilities.debugNotice("Modified Global Securty Domain App Security settings state to " + app_enable + " for the global security domain ")

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
