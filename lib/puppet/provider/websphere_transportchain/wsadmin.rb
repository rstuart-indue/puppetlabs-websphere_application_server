# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_transportchain).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a WebContainer Transport Chain at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=service-working-tcp-inbound-channel-properties-files
    https://www.ibm.com/docs/en/was/9.0.5?topic=service-working-ssl-inbound-channel-properties-files
    https://www.ibm.com/docs/en/was/9.0.5?topic=service-working-http-inbound-channel-properties-files
    https://www.ibm.com/docs/en/was/9.0.5?topic=service-working-web-container-inbound-channel-properties-files

    It is recommended to consult the IBM documentation as the WebContainer Transport Chains subject is very
    obscure and requires numerous blood sacrifices.

    This provider will not allow the changing of:
      * resource the template
      * the name of the resource.
    You need to destroy it first, then create another one with the desired attributes.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize(val = {})
    super(val)
    @property_flush = {}
    @old_chain_data = {}
    @old_tcp_data   = {}
    @old_ssl_data   = {}
    @old_http_data  = {}
    @old_wcc_data   = {}

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"

    index = file + "/config/cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/serverindex.xml"
    query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/Server:#{resource[:server]}"
    mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}"
    file += "/config/cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}/server.xml"

    case what
    when 'query'
      query
    when 'mod'
      mod
    when 'file'
      file
    when 'index'
      index
    else
      debug 'Invalid scope request'
    end
  end

  # Helper method to retrieve data out of a given channel.
  def getTransportChannelData (channel_id, xml_entry)
    channel_data = {}
    channel_entry = XPath.first(xml_entry, "transportChannels[@xmi:id='#{channel_id}']") unless channel_id.nil?
    debug "Loading existing #{channel_id} data attributes/values:"
    XPath.each(channel_entry, "@*")  { |attr|
      debug "#{attr.name} => #{attr.value}"
      channel_data[attr.name.to_sym] = attr.value
    } unless channel_entry.nil?

    return channel_data
  end

  # Helper method to convert a given hash of params into an array of arrays which is used by
  # the Jython code to set an object's attributes.
  def makeWASParams(source_hash, initial_array: [])
    raise Puppet::Error, 'Puppet::Provider::Websphere_TransportChain::wsadmin:makeWASParams(): source_hash argument must be a hash' unless source_hash.kind_of?(Hash)
    raise Puppet::Error, 'Puppet::Provider::Websphere_TransportChain::wsadmin:makeWASParams(): initial_array argument must be an array' unless initial_array.kind_of?(Array)

    initial_array += (source_hash.map{|k,v|[[k.to_s, v]]}).to_a unless source_hash.nil?
    was_params_str = initial_array.to_s.tr("\"", "'")
  end

  # Create a Web Container Transport Chain
  def create

    # Set the scope for this Transport Chain Resource.
    scope = scope('query') 

    tcp_attrs_str  = makeWASParams(resource[:tcp_inbound_channel], initial_array: [['endPointName', "#{resource[:end_point_name]}"]])
    ssl_attrs_str  = makeWASParams(resource[:ssl_inbound_channel])
    http_attrs_str = makeWASParams(resource[:http_inbound_channel])
    wcc_attrs_str  = makeWASParams(resource[:wcc_inbound_channel])

    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Web Container Transport Chain
scope = '#{scope}'
template = "#{resource[:template].to_s}"
name = "#{resource[:tc_name]}"
chainEnabled = "#{resource[:enabled]}"
endpoint = "#{resource[:endpoint_name]}"
endpoint_data = #{resource[:endpoint_details]}
tcp_attrs = #{tcp_attrs_str}
ssl_attrs = #{ssl_attrs_str}
http_attrs = #{http_attrs_str}
wcc_attrs = #{wcc_attrs_str}

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

def getEndpointID(endPointName):
  node_scope = '/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/'
  endPointID = ''
  for NEP in AdminConfig.list('NamedEndPoint', AdminConfig.getid(node_scope)).splitlines():
    if (AdminConfig.showAttribute(NEP, 'endPointName') == endPointName):
      endPointID = NEP
      break
    #endIf
  return endPointID
#endDef

def createWCTransportChain(scope, template, name, chainEnabled, endPointName, endPointData=[], tcpAttrsList=[], sslAttrsList=[], httpAttrsList=[], wccAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createWCTransportChain(" + `scope` + ", " + `template`+ ", " + `name`+ ", " + `chainEnabled` + ", " + `endPointName` + ", " + `endPointData` + ", " + `tcpAttrsList` + ", " + `sslAttrsList` + ", " + `httpAttrsList` + ", " + `wccAttrsList` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a WebContainer Transport Chain
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      " +scope)
    AdminUtilities.debugNotice (" Template:")
    AdminUtilities.debugNotice ("     template:                   " +template)
    AdminUtilities.debugNotice (" WebContainer TransportChain:")
    AdminUtilities.debugNotice ("     name:                       " +name)
    AdminUtilities.debugNotice ("     enabled:                    " +chainEnabled)
    AdminUtilities.debugNotice ("     endpoint name:              " +endPointName)
    AdminUtilities.debugNotice ("     endpoint data:              " +str(endPointData))
    AdminUtilities.debugNotice (" Optional Parameters :")
    AdminUtilities.debugNotice ("   TCP Attributes List:          " +str(tcpAttrsList))
    AdminUtilities.debugNotice ("   SSL Attributes List:          " +str(sslAttrsList))
    AdminUtilities.debugNotice ("   HTTP Attributes List:         " +str(httpAttrsList))
    AdminUtilities.debugNotice ("   WCC Attributes List:          " +str(wccAttrsList))
    AdminUtilities.debugNotice (" Return: The Configuration Id of the new WC Transport Chain")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")
    
    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(template) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["template", template]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(chainEnabled) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["chainEnabled", chainEnabled]))
    if (len(endPointName) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["endPointName", endPointName]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Get the template id - this returns an empty string if the template name is bogus
    templateID = AdminConfig.listTemplates('Chain', template)
    if (len(templateID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["templateID", templateID]))

    # Get the Transport Channel Service ID
    tcsID = AdminConfig.list( 'TransportChannelService',  configIdScope)
    if (len(tcsID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["tcsID", tcsID]))

    # Try to find the specified endpoint name. We're not going to look for the data match, since that
    # is not really our job - this is not different from the using of the Web UI
    namedEndPoint = getEndpointID(endPointName)

    if (len(namedEndPoint) == 0 ):
      AdminUtilities.debugNotice("Endpoint name: " +endPointName +" does not exist, will need to be created.")
      if (len(endPointData) == 0):
        raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["endPointData", endPointData]))
      #endIf

      # We have all the data to create a named endpoint - create it and return its ID
      endPointDetails = '[-name ' + str(endPointName) + ' -host ' + str(endPointData[0]) + ' -port ' + str(endPointData[1]) +']'     
      AdminUtilities.debugNotice("About to call AdminTask command to create named enpoint with details : " + str(endPointDetails))

      # Create the Named Endpoint
      namedEndPoint = AdminTask.createTCPEndPoint(tcsID, endPointDetails)
    #endIf

    chainDetails = '[-template ' + str(templateID) + ' -name ' + name + ' -endPoint ' + namedEndPoint +']'
    AdminUtilities.debugNotice("About to call AdminTask command to create chain with parameters : " + str(chainDetails))

    # Create the Transport Chain
    chainID = AdminTask.createChain(tcsID, chainDetails)

    # Get the Transport Channels for the created chain (gotta mangle the output string a little)
    # If we don't have a list of parameters we just move on.
    for transportChannel in AdminConfig.show(chainID, 'transportChannels')[20:-2].split(' '):
      if (tcpAttrsList and re.search('^TCP_.+TCPInboundChannel_.+', transportChannel)):
        tcpAttrsList = normalizeArgList(tcpAttrsList, "tcpAttrsList")
        AdminUtilities.debugNotice("Updating TCP Inbound Channel with params : " + str(tcpAttrsList))
        AdminConfig.modify(transportChannel, str(tcpAttrsList).replace(',', ''))
        continue
      elif (sslAttrsList and re.search('^SSL_.+SSLInboundChannel_.+', transportChannel)):
        sslAttrsList = normalizeArgList(sslAttrsList, "sslAttrsList")
        AdminUtilities.debugNotice("Updating SSL Inbound Channel with params : " + str(sslAttrsList))
        AdminConfig.modify(transportChannel, str(sslAttrsList).replace(',', ''))
        continue
      elif (httpAttrsList and re.search('^HTTP_.+HTTPInboundChannel_.+', transportChannel)):
        httpAttrsList = normalizeArgList(httpAttrsList, "httpAttrsList")
        AdminUtilities.debugNotice("Updating HTTP Inbound Channel with params : " + str(httpAttrsList))
        AdminConfig.modify(transportChannel, str(httpAttrsList).replace(',', ''))
        continue
      elif (wccAttrsList and re.search('^WCC_.+WebContainerInboundChannel_.+', transportChannel)):
        wccAttrsList = normalizeArgList(wccAttrsList, "wccAttrsList")
        AdminUtilities.debugNotice("Updating WCC Inbound Channel with params : " + str(wccAttrsList))
        AdminConfig.modify(transportChannel, str(wccAttrsList).replace(',', ''))
        continue
      else:
        AdminUtilities.debugNotice("Nothing to do about transport channel ID: " +transportChannel)
        continue
      #endIf
    #endFor

    # Save this Transport Chain
    AdminConfig.save()

    # Return the config ID of the newly created Chain object
    AdminUtilities.debugNotice("Returning config id of new Chain object : " + str(chainID))
    return chainID

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

# And now - create the Transport Chain
createWCTransportChain(scope, template, name, chainEnabled, endpoint, endpoint_data, tcp_attrs, ssl_attrs, http_attrs, wcc_attrs)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Web Container Transport Chain: #{resource[:tc_name]} of template #{resource[:template]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Web Container Transport Chain exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    doc = File.open(scope('file'))

    debug "Retrieving value of #{resource[:tc_name]} from #{scope('file')}"
    doc = REXML::Document.new(doc)

    # We're looking for Web Container Transport Chain entries matching our tc_name. We have to ensure we're looking under the
    # correct server entry - which is why we're checking for the server and cluster name - to be sure, to be sure.
    tcs_entry = XPath.first(doc, "/process:Server[@name='#{resource[:server]}'][@clusterName='#{resource[:cluster]}']/services[@xmi:type='channelservice:TransportChannelService']/")
    chain_entry = XPath.first(tcs_entry, "chains[@name='#{resource[:tc_name]}']") unless tcs_entry.nil?
    XPath.each(chain_entry, "@*") { |attr|
      debug "Chain #{attr.name} => #{attr.value}"
      attr_name = attr.name
      attr_value = attr.value
     if attr_name == 'transportChannels'
      @old_chain_data[attr_name.to_sym] = attr_value.split(' ')
     else
      @old_chain_data[attr_name.to_sym] = attr_value       
     end
    } unless chain_entry.nil?

    if (!chain_entry.nil?)
      # We're only looking for these types of channels. Long term - perhaps this module should be using a
      # whole different approach.
      tcp_in_channel_id  = @old_chain_data[:transportChannels].grep(/^TCPInboundChannel_\d+$/)
      ssl_in_channel_id  = @old_chain_data[:transportChannels].grep(/^SSLInboundChannel_\d+$/)
      http_in_channel_id = @old_chain_data[:transportChannels].grep(/^HTTPInboundChannel_\d+$/)
      wcc_in_channel_id  = @old_chain_data[:transportChannels].grep(/^WebContainerInboundChannel_\d+$/)

      @old_tcp_data  = getTransportChannelData(tcp_in_channel_id[0], tcs_entry) unless tcp_in_channel_id.nil?
      @old_ssl_data  = getTransportChannelData(ssl_in_channel_id[0], tcs_entry) unless ssl_in_channel_id.nil?
      @old_http_data = getTransportChannelData(http_in_channel_id[0], tcs_entry) unless http_in_channel_id.nil?
      @old_wcc_data  = getTransportChannelData(wcc_in_channel_id[0], tcs_entry) unless wcc_in_channel_id.nil?

      debug "Exists? method result for #{resource[:tc_name]} is: #{chain_entry}"
    end

    !chain_entry.nil?
  end

  # Get a chain's enabled status
  def enabled
    @old_chain_data[:enabled]
  end

  # Set a chain's enabled status
  def enabled=(val)
    @property_flush[:enabled] = val
  end

  # Get a chain's endpoint name
  def endpoint_name
    @old_tcp_data[:endPointName]
  end

  # Set a chain's endpoint name
  def endpoint_name=(val)
    @property_flush[:endPointName] = val
  end

  # Get a the TCP Inbound Channel data
  def tcp_inbound_channel
    @old_tcp_data
  end

  # Set the TCP Inbound Channel data
  def tcp_inbound_channel=(val)
    @property_flush[:tcp_data] = val
  end

  # Get a the SSL Inbound Channel data
  def ssl_inbound_channel
    @old_ssl_data
  end

  # Set the SSL Inbound Channel data
  def ssl_inbound_channel=(val)
    @property_flush[:ssl_data] = val
  end

  # Get a the HTTP Inbound Channel data
  def http_inbound_channel
    @old_http_data
  end

  # Set the HTTP Inbound Channel data
  def http_inbound_channel=(val)
    @property_flush[:http_data] = val
  end

  # Get a the WCC Inbound Channel data
  def wcc_inbound_channel
    @old_wcc_data
  end

  # Set the WCC Inbound Channel data
  def wcc_inbound_channel=(val)
    @property_flush[:wcc_data] = val
  end

  # Remove a given Web Container Transport Chain
  def destroy

    # Set the scope for this Transport Chain Resource.
    scope = scope('query')
    
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Web Container Transport Chain removal
scope = '#{scope}'
name = "#{resource[:tc_name]}"
endpoint = '#{resource[:endpoint_name]}

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteWCTransportChain(scope, name, endPoint, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteWCTransportChain(" + `scope` + ", " + `name`+ ", " + `endPoint`+ ", " +`failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a WebContainer Transport Chain
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      " +scope)
    AdminUtilities.debugNotice (" WebContainer Transport Chain:")
    AdminUtilities.debugNotice ("     name:                       " +name)
    AdminUtilities.debugNotice ("     end point:                  " +endPoint)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(endPoint) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["endPoint", endPoint]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Get the Transport Channel Service ID
    tcsID = AdminConfig.list( 'TransportChannelService',  configIdScope)
    if (len(tcsID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["tcsID", tcsID]))

    endPointFilter = '[-endPointFilter ' + endPoint +']'
    tcList = AdminTask.listChains(tcsID, endPointFilter).splitlines()

    tcRegex = re.compile("%s\\(.*" % name)

    target=list(filter(tcRegex.match, tcList))
    if (len(target) == 1):
      # Call the corresponding AdminTask command
      AdminUtilities.debugNotice("About to delete chain %s in scope %s. " % (str(target), str(configIdScope)))

      # Delete the Transport Chain and its associated channels
      AdminTask.deleteChain(str(target[0]), '[-deleteChannels true]') 

      AdminConfig.save()
    elif (len(target) == 0):
      raise AttributeError("Unable to find removal chain target %s in scope: %s" % (name, str(configIdScope)))
    elif (len(target) > 1):
      raise AttributeError("Too many chain targets for removal found: %s" % str(target))
    #endif

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

# And now - delete the Transport Chain
deleteWCTransportChain(scope, name, endpoint)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?
    # Set the scope for this Transport Chain Resource.
    scope = scope('query') 

    # Set the endpoint Name in this TCP Attributes
    tcp_attrs_str  = makeWASParams(resource[:tcp_inbound_channel], initial_array: [['endPointName', "#{resource[:end_point_name]}"]])
    ssl_attrs_str  = makeWASParams(resource[:ssl_inbound_channel])
    http_attrs_str = makeWASParams(resource[:http_inbound_channel])
    wcc_attrs_str  = makeWASParams(resource[:wcc_inbound_channel])

    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Web Container Transport Chain
scope = '#{scope}'
template = "#{resource[:template].to_s}"
name = "#{resource[:tc_name]}"
chainEnabled = "#{resource[:enabled]}"
endpoint = "#{resource[:endpoint_name]}"
endpoint_data = #{resource[:endpoint_details]}
tcp_attrs = #{tcp_attrs_str}
ssl_attrs = #{ssl_attrs_str}
http_attrs = #{http_attrs_str}
wcc_attrs = #{wcc_attrs_str}

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

def getEndpointID(endPointName):
  node_scope = '/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/'
  endPointID = ''
  for NEP in AdminConfig.list('NamedEndPoint', AdminConfig.getid(node_scope)).splitlines():
    if (AdminConfig.showAttribute(NEP, 'endPointName') == endPointName):
      endPointID = NEP
      break
    #endIf
  return endPointID
#endDef

def modifyWCTransportChain(scope, name, chainEnabled, endPointName, endPointData=[], tcpAttrsList=[], sslAttrsList=[], httpAttrsList=[], wccAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "modifyWCTransportChain(" + `scope` + ", " + `name`+ ", " + `chainEnabled` + ", " + `endPointName` + ", " + `endPointData` + ", " + `tcpAttrsList` + ", " + `sslAttrsList` + ", " + `httpAttrsList` + ", " + `wccAttrsList` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Modify a WebContainer Transport Chain
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      " +scope)
    AdminUtilities.debugNotice (" WebContainer TransportChain:")
    AdminUtilities.debugNotice ("     name:                       " +name)
    AdminUtilities.debugNotice ("     enabled:                    " +chainEnabled)
    AdminUtilities.debugNotice ("     endpoint name:              " +endPointName)
    AdminUtilities.debugNotice ("     endpoint data:              " +str(endPointData))
    AdminUtilities.debugNotice (" Optional Parameters :")
    AdminUtilities.debugNotice ("   TCP Attributes List:          " +str(tcpAttrsList))
    AdminUtilities.debugNotice ("   SSL Attributes List:          " +str(sslAttrsList))
    AdminUtilities.debugNotice ("   HTTP Attributes List:         " +str(httpAttrsList))
    AdminUtilities.debugNotice ("   WCC Attributes List:          " +str(wccAttrsList))
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")
    
    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(chainEnabled) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["chainEnabled", chainEnabled]))
    if (len(endPointName) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["endPointName", endPointName]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Get the Transport Channel Service ID
    tcsID = AdminConfig.list( 'TransportChannelService',  configIdScope)
    if (len(tcsID) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["tcsID", tcsID]))

    # Try to find the specified endpoint name. We're not going to look for the data match, since that
    # is not really our job - this is not different from the using of the Web UI
    namedEndPoint = getEndpointID(endPointName)

    if (len(namedEndPoint) == 0 ):
      AdminUtilities.debugNotice("Endpoint name: " +endPointName +" does not exist, will need to be created.")
      if (len(endPointData) == 0):
        raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["endPointData", endPointData]))
      #endIf

      # We have all the data to create a named endpoint - create it and return its ID
      endPointDetails = '[-name ' + str(endPointName) + ' -host ' + str(endPointData[0]) + ' -port ' + str(endPointData[1]) +']'     
      AdminUtilities.debugNotice("About to call AdminTask command to create named enpoint with details : " + str(endPointDetails))

      # Create the Named Endpoint
      namedEndPoint = AdminTask.createTCPEndPoint(tcsID, endPointDetails)
    #endIf

    # TODO: this is going to be interesting if we need to change the EndPoint - we can't search with it as filter... 
    #endPointFilter = '[-endPointFilter ' + endPoint +']'
    #tcList = AdminTask.listChains(tcsID, endPointFilter).splitlines()
    tcList = AdminTask.listChains(tcsID).splitlines()

    tcRegex = re.compile("%s\\(.*" % name)

    chainID = list(filter(tcRegex.match, tcList))
    if (len(chainID) == 0):
      raise AttributeError("Unable to find modification chain target %s in scope: %s" % (name, str(configIdScope)))
    elif (len(chainID) > 1):
      raise AttributeError("Too many chain targets for modification found: %s" % str(chainID))
    #endif

    chainDetailsList = [['name', name], ['enable', chainEnabled]]
    AdminUtilities.debugNotice("About to modify chain %s with parameters: %s" % (str(chainID), str(chainDetailsList)))

    AdminConfig.modify(chainID, str(chainDetailsList).replace(',', '')) 

    # Get the Transport Channels for the created chain (gotta mangle the output string a little)
    # If we don't have a list of parameters we just move on.
    for transportChannel in AdminConfig.show(chainID, 'transportChannels')[20:-2].split(' '):
      if (tcpAttrsList and re.search('^TCP_.+TCPInboundChannel_.+', transportChannel)):
        tcpAttrsList = normalizeArgList(tcpAttrsList, "tcpAttrsList")
        AdminUtilities.debugNotice("Updating TCP Inbound Channel with params : " + str(tcpAttrsList))
        AdminConfig.modify(transportChannel, str(tcpAttrsList).replace(',', ''))
        continue
      elif (sslAttrsList and re.search('^SSL_.+SSLInboundChannel_.+', transportChannel)):
        sslAttrsList = normalizeArgList(sslAttrsList, "sslAttrsList")
        AdminUtilities.debugNotice("Updating SSL Inbound Channel with params : " + str(sslAttrsList))
        AdminConfig.modify(transportChannel, str(sslAttrsList).replace(',', ''))
        continue
      elif (httpAttrsList and re.search('^HTTP_.+HTTPInboundChannel_.+', transportChannel)):
        httpAttrsList = normalizeArgList(httpAttrsList, "httpAttrsList")
        AdminUtilities.debugNotice("Updating HTTP Inbound Channel with params : " + str(httpAttrsList))
        AdminConfig.modify(transportChannel, str(httpAttrsList).replace(',', ''))
        continue
      elif (wccAttrsList and re.search('^WCC_.+WebContainerInboundChannel_.+', transportChannel)):
        wccAttrsList = normalizeArgList(wccAttrsList, "wccAttrsList")
        AdminUtilities.debugNotice("Updating WCC Inbound Channel with params : " + str(wccAttrsList))
        AdminConfig.modify(transportChannel, str(wccAttrsList).replace(',', ''))
        continue
      else:
        AdminUtilities.debugNotice("Nothing to do about transport channel ID: " +transportChannel)
        continue
      #endIf
    #endFor

    # Save this Transport Chain
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

# And now - modify the Transport Chain
modifyWCTransportChain(scope, name, chainEnabled, endpoint, endpoint_data, tcp_attrs, ssl_attrs, http_attrs, wcc_attrs)

END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
