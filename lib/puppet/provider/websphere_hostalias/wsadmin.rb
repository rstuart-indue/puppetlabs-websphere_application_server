# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_hostalias).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a host alias for a specific Virtual Host.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-creating-new-virtual-hosts-using-templates

    It is recommended to consult the IBM documentation for further clarifications.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  def initialize(val = {})
    super(val)

    @alias_id = ''

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  def scope(what, target_scope: resource[:scope])
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"

    debug "Using target_scope: #{target_scope}"

    # I don't honestly know where the query/mod could be used, but sure as hell
    # the xml entry is used in security.xml scope attribute for a management scope.
    # It's yet another way of defining scope in WAS.
    case target_scope
    when 'cell'
      query = "/Cell:#{resource[:cell]}"
      mod   = "cells/#{resource[:cell]}"
      xml   = "(cell):#{resource[:cell]}"
    else
      raise Puppet::Error, "Unknown scope: #{target_scope}"
    end

    file += "/config/cells/#{resource[:cell]}/virtualhosts.xml"

    case what
    when 'query'
      query
    when 'mod'
      mod
    when 'xml'
      xml
    when 'file'
      file
    else
      debug 'Invalid scope request'
    end
  end

  # Create an hostname - port alias pair for the given Virtual Host
  def create
    # Set the scope for this Virtual Host.
    scope = scope('query')
    
    # So I'm going to cheat a little:
    vhost_id = "#{scope('query')}/VirtualHost:#{resource[:virtual_host]}/"

    vhost_alias_list_str = [['hostname', resource[:hostname]], ['port', resource[:portnumber]]].to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our Host Alias
vhost_id= "#{vhost_id}"
vhost_scope = "#{scope}"
vhost_alias = #{vhost_alias_list_str}

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def normalizeArgList(argList, argName):
  if (argList == []):
    AdminUtilities.debugNotice ("No " + `argName` + " parameters specified. Continuing with defaults.")
  else:
    if (str(argList).startswith("[[") > 0 and str(argList).startswith("[[[",0,3) == 0):
      if (str(argList).find("\\"") > 0):
        argList = str(argList).replace("\\"", "\\'")
    else:
        raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6049E", [argList]))
  return argList
#endDef

def createVHostAlias(vhostID, scope, vHostAliasList, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createVHostAlias(" + `vhostID` +  ", " + `scope`+ `vHostAliasList` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a Host Alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminConfig: createVHostAlias ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     scope                       "+scope)
    AdminUtilities.debugNotice ("     vhostID                     "+vhostID)
    AdminUtilities.debugNotice (" Host Alias / Port:")
    AdminUtilities.debugNotice ("     vHostAliasList:             "+str(vHostAliasList))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    vHostAliasList = normalizeArgList(vHostAliasList, "vHostAliasList")
    
    # Make sure required parameters are non-empty
    if (len(vhostID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["vhostID", vhostID]))
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (vHostAliasList == [[]]):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["vHostAliasList", vHostAliasList]))

    # Prepare the parameters for the AdminConfig command:
    vHostAliasList = AdminUtilities.convertParamStringToList(vHostAliasList)
 
    # Call the corresponding AdminConfig command
    AdminUtilities.debugNotice("About to call AdminConfig command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminConfig command with parameters: " + str(vHostAliasList))

    # Create the Host Alias
    AdminConfig.create('HostAlias', AdminConfig.getid(vhostID), vHostAliasList)

    # Save this Host Alias
    AdminConfig.save()

  except:
    typ, val, tb = sys.exc_info()
    if (typ==SystemExit):  raise SystemExit,`val`
    if (failonerror != AdminUtilities._TRUE_):
      print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
      val = "%s %s" % (sys.exc_type, sys.exc_value)
      raise Exception("ScriptLibraryException: " + val)
    else:
      return AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
    #endIf
  #endTry
#endDef

# And now - create the Host Alias in the target store.
createVHostAlias(vhost_id, vhost_scope, vhost_alias)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Host Alias alias: #{resource[:virtual_host]} for location #{resource[:cell]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Virtual Host exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:virtual_host]}/#{resource[:hostname]}(#{resource[:portnumber]}) from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    xmi_entry = XPath.first(doc, "/xmi:XMI")
    host_entry = XPath.first(xmi_entry, "host:VirtualHost[@name='#{resource[:virtual_host]}']/") unless xmi_entry.nil?
    debug "Found Virtual Host entry for '#{resource[:virtual_host]}'." unless host_entry.nil?

    # Make sure we don't look for a port number if the defined port is 80. WAS does not mention it
    # in the config if the port number is the default 80.
    if resource[:portnumber] == 80
      alias_entry = XPath.first(host_entry, "aliases[@hostname='#{resource[:hostname]}']") unless host_entry.nil?
    else
      alias_entry = XPath.first(host_entry, "aliases[@hostname='#{resource[:hostname]}'][@port='#{resource[:portnumber]}']") unless host_entry.nil?
    end

    # Get the Alias ID while we're at it. We'll need it in order to delete the resource easier.
    @alias_id = XPath.match(alias_entry, "@*[local-name()='id']") unless alias_entry.nil?

    debug "Alias hostname/port for #{resource[:virtual_host]} is: #{alias_entry.attributes['hostname']}(#{alias_entry.attributes['port']}" unless alias_entry.nil?
    !alias_entry.nil?
  end

  # Remove a given Virtual Host
  def destroy

    # Set the scope for this vhost.
    scope = scope('query')
    
    # So I'm going to cheat a little:
    hostalias_id = "#{scope('query')}|virtualhosts.xml##{@alias_id}"

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our Host Alias removal
alias_id = '(#{hostalias_id})' 

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteVHostAlias(hostAliasID, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteVHostAlias(" + `hostAliasID` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete an Alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminConfig: deleteVHostAlias ")
    AdminUtilities.debugNotice (" Host Alias ID:")
    AdminUtilities.debugNotice ("     host alias:                    "+hostAliasID)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(hostAliasID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["hostAliasID", hostAliasID]))

    # Call the corresponding AdminConfig command
    AdminUtilities.debugNotice("About to call AdminConfig command for target Virtual Host alias: " + str(hostAliasID))

    # Delete the Virtual Host
    AdminConfig.remove(hostAliasID)

    AdminConfig.save()

  except:
    typ, val, tb = sys.exc_info()
    if (typ==SystemExit):  raise SystemExit,`val`
    if (failonerror != AdminUtilities._TRUE_):
      print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
      val = "%s %s" % (sys.exc_type, sys.exc_value)
      raise Exception("ScriptLibraryException: " + val)
    else:
      return AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
    #endIf
  #endTry
#endDef

# And now - delete the host alias
deleteVHostAlias(alias_id)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    super()
  end
end