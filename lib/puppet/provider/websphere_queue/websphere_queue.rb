# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_queue).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a JMS Queue for the IBM MQ messaging provider at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-createwmqqueue-command
    https://www.ibm.com/docs/en/was-nd/9.0.5?topic=cws-mapping-administrative-console-panel-names-command-names-mq-names

    It is recommended to consult the IBM documentation as the JMS queue subject is relatively complex and difficult to abstract.

    This provider will not allow the creation of a dummy instance (i.e. no MQ server target)
    This provider will now allow the changing of:
      * the name of the Queue
      * the scope of the Queue.
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
    @old_q_data = {}
    @old_custom_properties = {}

    # This hash acts as a translation table between what shows up in the XML file
    # and what the Jython parameters really are. Its format is:
    # 'XML key' => 'Jython param'
    #
    # This translation table allows us to match what we find in the XML files
    # and what we have configured via Jython and see if anything changed.
    # For many of the Jython params, they have identical correspondents in the
    # XML file, but some notable ones are not quite the same.
    #
    # TODO: It would be nice if the translation-table was extendable at runtime, so that
    #       the user can add more translations as they see fit, instead of
    #       waiting for someone to change the provider.
    @xlate_val_table = {
      'APPLICATION_DEFINED' => 'APP',
      'QUEUE_DEFINED' => 'QDEF',
      'PERSISTENT' => 'PERS',
      'NONPERSISTENT' => 'NON',
    }

    @xlate_cmd_table = {
      'CCSID' => 'ccsid',
    }

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    case resource[:scope]
    when 'cell'
      query = "/Cell:#{resource[:cell]}"
      mod   = "cells/#{resource[:cell]}"
      file += "/config/cells/#{resource[:cell]}/resources.xml"
    when 'cluster'
      query = "/Cell:#{resource[:cell]}/ServerCluster:#{resource[:cluster]}"
      mod   = "cells/#{resource[:cell]}/clusters/#{resource[:cluster]}"
      file += "/config/cells/#{resource[:cell]}/clusters/#{resource[:cluster]}/resources.xml"
    when 'node'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}"
      file += "/config/cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/resources.xml"
    when 'server'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/Server:#{resource[:server]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}"
      file += "/config/cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}/resources.xml"
    else
      raise Puppet::Error, "Unknown scope: #{resource[:scope]}"
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

  # Create a JMS Queue
  def create

    # Set the scope for this JMS Resource.
    jms_scope = scope('query') 

    # At the very least - we pass the description of the Queue.
    q_attrs = [["description", "#{resource[:description]}"]]
    q_attrs += (resource[:q_data].map{|k,v| [k.to_s, v]}).to_a unless resource[:q_data].nil?
    q_attrs_str = q_attrs.to_s.tr("\"", "'")

    custom_attrs = []
    custom_attrs = (resource[:custom_properties].map{|k,v| [k.to_s, v]}).to_a unless resource[:custom_properties].nil?
    custom_attrs_str = custom_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our Queue
scope = '#{jms_scope}'
name = "#{resource[:q_name]}"
jndiName = "#{resource[:jndi_name]}"
queueName = "#{resource[:queue_name]}"
attrs = #{q_attrs_str}
custom_attrs = #{custom_attrs_str}

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

def createWMQQueue(scope, name, jndiName, queueName, attrsList=[], customAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createWMQQueue(" + `scope` + ", " + `name`+ ", " + `jndiName` + ", " + `queueName` + ", " + `attrsList` + ", " + `customAttrsList` + ", " + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a WMQ Queue
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminJMS: createWMQQueue")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" MQQueue:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice ("     jndiName:                   "+jndiName)
    AdminUtilities.debugNotice ("     queueName:                  "+queueName)
    AdminUtilities.debugNotice (" Optional Parameters :")
    AdminUtilities.debugNotice ("     AttributesList:             " +str(attrsList))
    AdminUtilities.debugNotice ("     CustomAttributesList:       " +str(customAttrsList))
    AdminUtilities.debugNotice (" Return: The Configuration Id of the new WMQ Queue")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    attrsList = normalizeArgList(attrsList, "attrsList")
    customAttrsList = normalizeArgList(customAttrsList, "customAttrsList")
    
    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(jndiName) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["jndiName", jndiName]))
    if (len(cftype) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["queueName", queueName]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Prepare the parameters for the AdminTask command.
    attrsList = AdminUtilities.convertParamStringToList(attrsList)

    requiredParameters = [["name", name], ["jndiName", jndiName], ["queueName", queueName]]
    finalAttrsList = requiredParameters + attrsList
    finalParameters = []
    for attrs in finalAttrsList:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with target : " + str(configIdScope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters : " + str(finalParameters))

    # Create the Queue
    newObjectId = AdminTask.createWMQQueue(configIdScope, finalParameters)

#    # Set the custom Attributes list - the parameter takes a mangled array of arrays with no commas
#    if customAttrsList:
#      sessionPool = AdminConfig.showAttribute(newObjectId, 'sessionPool')
#      AdminConfig.modify(sessionPool, str(customAttrsList).replace(',', ''))
#
    newObjectId = str(newObjectId)

    # Save this Queue
    AdminConfig.save()

    # Return the config ID of the newly created object
    AdminUtilities.debugNotice("Returning config id of new object : " + str(newObjectId))
    return newObjectId

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

# And now - create the queue
createWMQQueue(scope, name, jndiName, queueName, attrs, custom_attrs)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Queuee: #{resource[:q_name]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Queue exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    # This sounds mad, but it is possible to store different strange objects as
    # resources. I've found .zip and .XML files so far stored as resourceProperties
    # at which point parsing the resources.xml file becomes incredibly slow (40seconds)
    # and intensive. The easiest way out of this is to excise those resourceProperties
    # based on a regexp and pass the remaining XML to the DOM parser.
    #
    # What we are trying to remove are constructs of this type:
    # <resourceProperties xmi:id="J2EEResourceProperty_1499488858500" name="widgetFeedUrlMap.xml" value="&lt;?xml version=&quot;..." ...>
    # <resourceProperties xmi:id="J2EEResourceProperty_1499488861016" name="SolutionAdministration.zip" value="UEsDBAoAAAAIABIaa..." ...>
    #
    # This is making an educated guess that you are not trying to admin something of
    # this kind. If you do, you have my condolences for your dearly departed sanity.
    xml_content = ''
    if resource[:sanitize] == :true && ( !resource[:ignored_names].empty? )
      suffix_list = resource[:ignored_names].join('|')
      File.open(scope('file')).each_line do |line|
        xml_content += line unless /<resourceProperties.*name="\w+\.(#{suffix_list})"/.match?(line)
      end
    else
      xml_content = File.open(scope('file'))
    end

    debug "Retrieving value of #{resource[:jms_provider]}/#{resource[:q_name]} from #{scope('file')}"
    doc = REXML::Document.new(xml_content)

    # We're looking for Queue entries matching our q_name. We have to ensure we're looking under the
    # correct provider entry.
    jms_entry = XPath.first(doc, "/xmi:XMI[@xmlns:resources.jms.mqseries]/resources.jms:JMSProvider[@xmi:id='#{resource[:jms_provider]}']")
    q_entry = XPath.first(jms_entry, "factories[@xmi:type='resources.jms.mqseries:MQQueue'][@name='#{resource[:q_name]}']") unless jms_entry.nil?

    # Populate the @old_q_data by discovering what are the params for the given Queue
    debug "Exists? method is loading existing Queue data attributes/values:"
    XPath.each(q_entry, "@*")  { |attr|
      debug "#{attr.name} => #{attr.value}"
      xlated_name = @xlate_cmd_table.key?(attr.name) ? @xlate_cmd_table[attr.name] : attr.name
      @old_q_data[xlated_name.to_sym] = attr.value
    } unless q_entry.nil?

    # Extract the connectionPool attributes
    #XPath.each(q_entry, "connectionPool/@*")  { |attr|
    #  debug "#{attr.name} => #{attr.value}"
    #  @old_conn_pool_data[attr.name.to_sym] = attr.value
    #} unless q_entry.nil?

    debug "Exists? method result for #{resource[:q_name]} is: #{q_entry}"

    !q_entry.nil?
  end

  # Get a Queue's JNDI
  def jndi_name
    @old_q_data[:jndiName]
  end

  # Set a Queue's JNDI
  def jndi_name=(val)
    @property_flush[:jndiName] = val
  end

  # Get a Queue's description
  def description
    @old_q_data[:description]
  end

  # Set a Queue's description
  def description=(val)
    @property_flush[:description] = val
  end

  # Get a Queue's QMGR Settings
  def q_data
    @old_q_data
  end

  # Set a Queue's QMGR Settings
  def q_data=(val)
    @property_flush[:q_data] = val
  end

  # Get a Queue's custom properties
  def custom_properties
    @custom_properties
  end

  # Set a Queue's custom properties
  def custom_properties=(val)
    @property_flush[:custom_properties] = val
  end

  # Remove a given Queue - we try to find it first
  def destroy

    # Set the scope for this JMS Resource.
    jms_scope = scope('query')
    
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Queue removal
scope = '#{jms_scope}'
name = "#{resource[:q_name]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteWMQQueue(scope, name, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteWMQQueue(" + `scope` + ", " + `name`+ ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a WMQ Queue
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminJMS: deleteWMQQueue ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" MQQueue:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Get the '\\n' separated string of queues and make a proper list out of them 
    qList=AdminTask.listWMQQueues(configIdScope).split('\\n')

    qRegex = re.compile("%s\\(.*" % name)

    target=list(filter(qRegex.match, qList))
    if (len(target) == 1):
      # Call the corresponding AdminTask command
      AdminUtilities.debugNotice("About to call AdminTask command with scope : " + str(configIdScope))
      AdminUtilities.debugNotice("About to call AdminTask command for target : " + str(target))

      # Delete the Queue
      AdminTask.deleteWMQQueue(str(target[0]))

      AdminConfig.save()
    elif (len(target) == 0):
      raise AttributeError("Unable to find removal target %s in scope: %s" % (name, str(configIdScope)))
    elif (len(target) > 1):
      raise AttributeError("Too many targets for removal found: %s" % str(target))
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

# And now - delete the queue
deleteWMQQueue(scope, name)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return unless @property_flush
    #
    # Ideally, only the changing params would be modified, alas, that is not how things are done.
    #
    # A bit of theory: It would appear that when you edit a JMS resource, the WAS UI re-applies
    # all the params associated with that JMS resource, whether they changed or not. Whilst that
    # seems odd, it perhaps makes sense - in order to re-validate the set of params which is now
    # changing shape. It's not entirely clear why they've chosen to do it this way, but until
    # proven otherwise, we're doing the same.
    #
    # Note: WAS will only delete/clear a param if it has a "no value" associated with it. Simply
    #       removing it from the list of managed params will NOT delete/clear it.
    #
    # Set the scope for this JMS Resource.
    jms_scope = scope('query') 

    # At the very least - we pass the description of the Queue.
    q_attrs = [["description", "#{resource[:description]}"]]
    q_attrs += (resource[:q_data].map{|k,v| [k.to_s, v]}).to_a unless resource[:q_data].nil?
    q_attrs_str = q_attrs.to_s.tr("\"", "'")

    custom_attrs = []
    custom_attrs = (resource[:custom_properties].map{|k,v| [k.to_s, v]}).to_a unless resource[:custom_properties].nil?
    custom_attrs_str = custom_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our Queue
scope = '#{jms_scope}'
name = "#{resource[:q_name]}"
jndiName = "#{resource[:jndi_name]}"
attrs = #{q_attrs_str}
custom_attrs = #{custom_attrs_str}

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

def modifyWMQQueue(scope, name, jndiName, qAttrsList=[], customAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "modifyWMQQueue(" + `scope` + ", " + `name`+ ", " + `jndiName` + ", " + `qAttrsList` + ", " + `customAttrsList` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Modify a WMQ Queue
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminJMS: modifyWMQQueue ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" MQQueue:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice ("     jndiName:                   "+jndiName)
    AdminUtilities.debugNotice (" Optional Parameters :")
    AdminUtilities.debugNotice ("   otherAttributesList:          " +str(qAttrsList))
    AdminUtilities.debugNotice ("   sessionPoolAttributesList:    " +str(customAttrsList))
    AdminUtilities.debugNotice (" Return: The Configuration Id of the new WM Queue")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    qAttrsList = normalizeArgList(qAttrsList, "qAttrsList")
    customAttrsList = normalizeArgList(customAttrsList, "customAttrsList")

    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(jndiName) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["jndiName", jndiName]))

    # Validate the scope
    # We will end up with a containment path for the scope - convert that to the config id which is needed.
    if (scope.find(".xml") > 0 and AdminConfig.getObjectType(scope) == None):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))
    scopeContainmentPath = AdminUtilities.getScopeContainmentPath(scope)
    configIdScope = AdminConfig.getid(scopeContainmentPath)

    # If at this point, we don't have a proper config id, then the scope specified was incorrect
    if (len(configIdScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

    # Get the '\\n' separated string of Connection Factories and make a proper list out of them 
    qList=AdminTask.listWMQConnectionFactories(configIdScope).split('\\n')

    qRegex = re.compile("%s\\(.*" % name)

    target=list(filter(qRegex.match, qList))
    if (len(target) == 1):
      # Call the corresponding AdminTask command
      AdminUtilities.debugNotice("About to call AdminTask command with scope : " + str(configIdScope))
      AdminUtilities.debugNotice("About to call AdminTask command for target : " + str(target))

      # Prepare the parameters for the AdminTask command
      qAttrsList = AdminUtilities.convertParamStringToList(qAttrsList)
      requiredParameters = [["name", name], ["jndiName", jndiName]]
      finalAttrsList = requiredParameters + qAttrsList
      finalParameters = []
      for attrs in finalAttrsList:
        attr = ["-"+attrs[0], attrs[1]]
        finalParameters = finalParameters+attr
  
      # Call the corresponding AdminTask command
      AdminUtilities.debugNotice("About to call AdminTask command with parameters : " + str(finalParameters))

      # Modify the Queue
      newObjectId = AdminTask.modifyWMQQueue(str(target[0]), finalParameters)

      # Set the custom attributes list - the modify() takes a mangled array of arrays with no commas
      #if customAttrsList:
      #  sessionPool = AdminConfig.showAttribute(newObjectId, 'sessionPool')
      #  AdminConfig.modify(sessionPool, str(customAttrsList).replace(',', ''))

      newObjectId = str(newObjectId)
  
      # Save this Queue
      AdminConfig.save()
  
      # Return the config ID of the newly created object
      AdminUtilities.debugNotice("Returning config id of new object : " + str(newObjectId))
      return newObjectId

      AdminConfig.save()
    elif (len(target) == 0):
      raise AttributeError("Unable to find modification target %s in scope: %s" % (name, str(configIdScope)))
    elif (len(target) > 1):
      raise AttributeError("Too many targets for modification found: %s" % str(target))
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

# And now - modify the Queue.
modifyWMQQueue(scope, name, jndiName, attrs, custom_attrs)

END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
