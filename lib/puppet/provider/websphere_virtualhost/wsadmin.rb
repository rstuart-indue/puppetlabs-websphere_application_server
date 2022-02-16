# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_virtualhost).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a Virtual Host at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-creating-new-virtual-hosts-using-templates

    It is recommended to consult the IBM documentation for further clarifications.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  def initialize(val = {})
    super(val)
    @property_flush = {}

    @old_conf_details = []

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
    when 'cluster'
      query = "/Cell:#{resource[:cell]}/ServerCluster:#{resource[:cluster]}"
      mod   = "cells/#{resource[:cell]}/clusters/#{resource[:cluster]}"
      xml   = "(cell):#{resource[:cell]}:(cluster):#{resource[:cluster]}"
    when 'node'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}"
      xml   = "(cell):#{resource[:cell]}:(node):#{resource[:node_name]}"
    when 'server'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/Server:#{resource[:server]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}"
      xml   = "(cell):#{resource[:cell]}:(node):#{resource[:node_name]}:(server):#{resource[:server]}"
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

  # Helper method to assemble the alias list in a format like below
  # ["aliases",
  #            [
  #             [["hostname", "*"], ["port", "9080"]],
  #             [["hostname", "*"], ["port", "80"]],
  #             [["hostname", "*"], ["port", "9443"]],
  #            ]
  # ]
  def get_aliases_string
    alias_list = []
    resource[:alias_list].each { |alias_pair|
      alias_list += [[['hostname', "#{alias_pair[0]}"], ['port', "#{alias_pair[1]}"]]]
    } unless resource[:alias_list].nil?
    vhost_alias_list = ['aliases', alias_list]
    vhost_alias_list.to_s.tr("\"", "'")
  end

  # Create a Virtual Host Resource
  def create
    # Set the scope for this Virtual HostResource.
     scope = scope('query')

    vhost_alias_list_str = get_aliases_string

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our Virtual Host
vhost_name = "#{resource[:'vhost']}"
vhost_scope = "#{scope}"
vhost_aliases = #{vhost_alias_list_str}

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

def createVHost(name, scope, vHostAliasList, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createVHost(" + `name` +  ", " + `scope`+ `vHostAliasList` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a Virtual Host
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminConfig: createVHost ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     scope                       "+scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" Virtual Host Aliases:")
    AdminUtilities.debugNotice ("     vHostAliasList:             "+str(vHostAliasList))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    vHostAliasList = normalizeArgList(vHostAliasList, "vHostAliasList")
    
    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))

    # Prepare the parameters for the AdminConfig command:
    vHostAliasList = AdminUtilities.convertParamStringToList(vHostAliasList)
    requiredParameters = [["name", name]]
    finalAttrsList = requiredParameters + vHostAliasList

    # Call the corresponding AdminConfig command
    AdminUtilities.debugNotice("About to call AdminConfig command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminConfig command with parameters: " + str(finalAttrsList))

    # Create the Virtual Host Alias
    AdminConfig.create( 'VirtualHost', AdminConfig.getid(scope), finalAttrsList)

    # Save this Virtual Host
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

# And now - create the Virtual Host in the target store.
createVHost(vhost_name, vhost_scope, vhost_aliases)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Virtual Host alias: #{resource[:'vhost']} for location #{resource[:cell]}
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

    debug "Retrieving value of #{resource[:'vhost']} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    xmi_entry = XPath.first(doc, "/xmi:XMI")
    host_entry = XPath.first(xmi_entry, "host:VirtualHost[@name='#{resource[:vhost]}']/") unless xmi_entry.nil?
    debug "Found Virtual Host entry for '#{resource[:vhost]}'." unless host_entry.nil?

    XPath.each(host_entry, "aliases") { |alias_entry|
      hostname, port = XPath.match(alias_entry, "@*[local-name()='hostname' or local-name()='port']")

      # If the port is not specified in an alias entry, it signifies it refers to port 80.
      port = port.nil? ? "80" : port.value.to_s
      @old_conf_details += [[hostname.value.to_s, port]]
    } unless host_entry.nil?

    debug "Virtual Host data for #{resource[:vhost]} is: #{@old_conf_details}"
    !host_entry.nil?
  end

  def alias_list
    @old_conf_details
  end

  def alias_list=(val)
    @property_flush[:alias_list] = val
  end

  # Remove a given Virtual Host
  def destroy

    # Set the scope for this vhost.
    scope = scope('query')
    
    # So I'm going to cheat a little:
    vhost_id = "#{scope('query')}/VirtualHost:#{resource[:vhost]}/"

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our VHost removal
scope = '#{scope}'
vhost_id = '#{vhost_id}' 

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteVHost(name, scope, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteVHost(" + `name` + ", " + `scope` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a Virtual Host
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminConfig: deleteVHost ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" Virtual Host ID:")
    AdminUtilities.debugNotice ("     name   :                    "+name)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))

    # Call the corresponding AdminConfig command
    AdminUtilities.debugNotice("About to call AdminConfig command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminConfig command for target Virtual Host alias: " + str(name))

    # Delete the Virtual Host
    AdminConfig.remove(AdminConfig.getid(name))

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

# And now - delete the certalias
deleteVHost(vhost_id, scope)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    # Set the scope for this VHost.
    scope = scope('query')

    vhost_alias_list_str = get_aliases_string

    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Virtual Host
vhost_name = "#{resource[:'vhost']}"
vhost_scope = "#{scope}"
vhost_aliases = #{vhost_alias_list_str}

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

END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
