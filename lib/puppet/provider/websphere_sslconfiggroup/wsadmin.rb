# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_sslconfiggroup).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create an SSL Config Group at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was-nd/9.0.5?topic=tool-sslconfiggroupcommands-group-admintask-object

    It is recommended to consult the IBM documentation.

    This provider will not allow the creation of a dummy instance - it requires valid SSL Configuration.

    This provider will not allow the changing of:
      * the name/alias of the SSL Config Group object
      * the direction of the SSL Config Group object.
    You need to destroy it first, and create another one with the desired attributes.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  def initialize(val = {})
    super(val)
    @property_flush = {}

    @old_conf_details = {}

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

    file += "/config/cells/#{resource[:cell]}/security.xml"

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

  # Create an SSL Config Group Resource
  def create
    # Set the scope for this SSL Config Group Resource.
     confgrp_scope = scope('xml')
  
    # Compute the SSL config scope
    sslconf_scope = scope('xml', target_scope: resource[:ssl_config_scope])

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our SSL Config Group
confgrp_name = "#{resource[:confgrp_alias]}"
confgrp_scope = "#{confgrp_scope}"
direction = "#{resource[:direction]}"
ssl_conf_alias = "#{resource[:ssl_config_name]}"
ssl_conf_scope = "#{sslconf_scope}"
c_cert = "#{resource[:client_cert_alias]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def createSSLConfigGroup(name, confgrp_scope, direction, sslConfAlias, sslConfScope, client_cert, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createSSLConfigGroup(" + `name` +  ", " + `confgrp_scope`+ ", " + `direction`+ ", " + `sslConfScope` + ", " + `sslConfAlias` + ", " + `client_cert` +  ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create an SSL Config Group
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminSSLConfig: createSSLConfigGroup ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     scope                       "+confgrp_scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice ("     direction:                  "+direction)
    AdminUtilities.debugNotice (" SSL Config and cert:")
    AdminUtilities.debugNotice ("     SSL Config:                 "+sslConfAlias)
    AdminUtilities.debugNotice ("     SSL Config Scope:           "+sslConfScope)
    AdminUtilities.debugNotice ("     clientcert:                 "+client_cert)
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(confgrp_scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["confgrp_scope", confgrp_scope]))
    if (len(direction) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["direction", direction]))
    if (len(sslConfScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["sslConfScope", sslConfScope]))
    if (len(sslConfAlias) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["sslConfAlias", sslConfAlias]))

    # Prepare the parameters for the AdminTask command:
    requiredParameters = [["name", name], ["scopeName", confgrp_scope], ["direction", direction], ["sslConfigScopeName", sslConfScope], ["sslConfigAliasName", sslConfAlias], ["certificateAlias", client_cert]]
    for attrs in requiredParameters:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(confgrp_scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Create the SSL Config Group Alias
    AdminTask.createSSLConfigGroup(finalParameters)

    # Save this SSL Config Group
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

# And now - Create the SSL Config Group in the target store.
createSSLConfigGroup(confgrp_name, confgrp_scope, direction, ssl_conf_alias, ssl_conf_scope, c_cert)
END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create SSL Config Group alias: #{resource[:confgrp_alias]} for direction #{resource[:direction]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if an SSL Config Group exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:confgrp_alias]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    sec_entry = XPath.first(doc, "/security:Security]")
    
    # This is a lot sillier than I hoped for. Basically the WAS security.xml is a dog's
    # breakfast with some of its XML functionality excised and its structure flattened.
    # Instead of using the category/subcategory/sub-subcategory/item structure, they
    # chose to use the attributes in an item or category to keep track of the parenthood
    # thereby flattening the XML structure and offloading the XML logic to the application.
    # So what we are trawling through is something like this:
    #
    #  <managementScopes xmi:id="ManagementScope_1" scopeName="(cell):CELL_01" scopeType="cell"/>
    #  <managementScopes xmi:id="ManagementScope_2" scopeName="(cell):CELL_01:(node):DMGR_01" scopeType="node"/>
    #  <managementScopes xmi:id="ManagementScope_34948" scopeName="(cell):CELL_01:(node):NODE01" scopeType="node"/>
    #  <managementScopes xmi:id="ManagementScope_50298" scopeName="(cell):CELL_01:(node):NODE02" scopeType="node"/>
    #  <repertoire xmi:id="SSLConfig_855" alias="TEST_KEYSTORE_SSLCONFIG" type="JSSE" managementScope="ManagementScope_1">
    #    <setting xmi:id="SecureSocketLayer_862" clientAuthentication="false" securityLevel="HIGH" enabledCiphers="" jsseProvider="IBMJSSE2" sslProtocol="SSL_TLSv2" keyStore="KeyStore_4308" trustStore="KeyStore_4308">
    #      <properties xmi:id="Property_690" name="com.ibm.ssl.changed" value="0"/>
    #      <properties xmi:id="Property_537" name="some.random.prop" value="some.random.value" description="Some Random Description" required="false"/>
    #    </setting>
    #  </repertoire>
    #  <sslConfigGroups xmi:id="SSLConfigGroup_1654731352187" name="SSL_CONF_GRP_cluster" direction="outbound" certificateAlias="hostname.fqdn_exp20240125" sslConfig="SSLConfig_855" managementScope="ManagementScope_1"/>


    # Note how "managementScope_1" is the attribute which ties the keyStores and SSL configs items to a managementScopes item.
    # Also, note how the references to the trust and keystores are done via the unique xmi:id identifiers.
    #
    # Aside to the fact that the managementScopes is there as a work-around for not having multiple security.xml files in
    # all the right places like we're having for the rest of the WAS settings
    #
    # So, with this said, what we have to do here is:
    #   * Find the appropriate management scope ID by working it back from the scope name (the XML one).
    #   * Find if we have an SSL config group with the given name in that particular management scope ID, and in that particular direction
    #   * Extract the config details from the entry attributes if we do find one.
    #   * Reverse lookup the SSL Config details so that we can marry them up with the given params
    #   * Hope that the cert-alias clear-listing does not change in the future - as that's the only thing
    #     we can pick up without having to mangle it in the process.

    
    # Turns out that the SSL Config Group name has to be unique within the given management scope.
    mgmt_scope = XPath.first(sec_entry, "managementScopes[@scopeName='#{scope('xml')}']/@*[local-name()='id']") unless sec_entry.nil?
    debug "Found Management Scope entry for scope '#{resource[:scope]}': #{mgmt_scope.value.to_s}" unless mgmt_scope.nil?

    confgrp_entry = XPath.first(sec_entry, "sslConfigGroups[@managementScope='#{mgmt_scope.value.to_s}'][@direction='#{@resource[:direction]}'][@name='#{@resource[:confgrp_alias]}']") unless mgmt_scope.nil?

    debug "Found SSL Config Group entry for scope #{scope('xml')}: #{confgrp_entry}" unless confgrp_entry.nil?

    XPath.each(confgrp_entry, "@*") { |attribute|
      attr_name = attribute.name.to_s
      attr_value = attribute.value.to_s
      case attr_name
      when 'sslConfig'
        # Reverse lookup the SSL Config ID to what its real name is. Get the scope and scope-type while
        # we're here. Certainly don't want to regexp this thing later.
        sslconf_name,sslconf_mgtscope = XPath.match(sec_entry, "repertoire[@xmi:id='#{attr_value}']/@*[local-name()='alias' or local-name()='managementScope']")
        sslconf_scope,sslconf_scope_type = XPath.match(sec_entry, "managementScopes[@xmi:id='#{sslconf_mgtscope.value.to_s}']/@*[local-name()='scopeName' or local-name()='scopeType']")
        @old_conf_details[attr_name.to_sym] = sslconf_name.value.to_s
        @old_conf_details["#{attr_name}Scope".to_sym] = sslconf_scope.value.to_s
        @old_conf_details["#{attr_name}ScopeType".to_sym] = sslconf_scope_type.value.to_s
      else
        @old_conf_details[attr_name.to_sym] = attr_value
      end    
    } unless confgrp_entry.nil?

    debug "SSL Config Group data for #{resource[:confgrp_alias]} is: #{@old_conf_details}"
    !confgrp_entry.nil?
  end

  def ssl_config_name
    @old_conf_details[:sslConfig]
  end

  def ssl_config_name=(val)
    @property_flush[:sslConfig] = val
  end

  def ssl_config_scope
    @old_conf_details[:sslConfigScope]
  end

  def ssl_config_scope=(val)
    @property_flush[:sslConfigScope] = val
  end

  def client_cert_alias
    @old_conf_details.key?(:certificateAlias)? @old_conf_details[:certificateAlias] : ''
  end

  def client_cert_alias=(val)
    @property_flush[:certificateAlias] = val
  end

  # Remove a given SSL Config Group
  def destroy

    # Set the scope for this Keystore/SSLConfig.
    confgrp_scope = scope('xml')
    
    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our SSLConfig Group removal
confgrp_scope = '#{confgrp_scope}'
config_alias = '#{resource[:confgrp_alias]}'
direction = "#{resource[:direction]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteSSLConfigGroup(name, scope, direction, failonerror=AdminUtilities._TRUE_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteSSLConfig(" + `name` + ", " + `scope` + ", " + `direction` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete an SSL Config Group
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminSSLConfig: deleteSSLConfig ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" SSL Config Group Alias:")
    AdminUtilities.debugNotice ("     name     :                  "+name)
    AdminUtilities.debugNotice ("     direction:                  "+direction)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminTask command for target SSL Config Group alias: " + str(name))

    # Delete the SSL Config Group
    AdminTask.deleteSSLConfigGroup(['-name', name, '-scopeName', scope, '-direction', direction])

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

# And now - delete the SSL Config Group
deleteSSLConfigGroup(config_alias, confgrp_scope, direction)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    # Set the scope for this Keystore/SSLConfig.
    confgrp_scope = scope('xml')

    # Compute the SSL config scope
    sslconf_scope = scope('xml', target_scope: resource[:ssl_config_scope])

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our SSL Config Group
confgrp_name = "#{resource[:confgrp_alias]}"
confgrp_scope = "#{confgrp_scope}"
direction = "#{resource[:direction]}"
ssl_conf_alias = "#{resource[:ssl_config_name]}"
ssl_conf_scope = "#{sslconf_scope}"
c_cert = "#{resource[:client_cert_alias]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def modifySSLConfigGroup(name, confgrp_scope, direction, sslConfAlias, sslConfScope, client_cert, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "modifySSLConfigGroup(" + `name` +  ", " + `confgrp_scope`+ ", " + `direction`+ ", " + `sslConfScope` + ", " + `sslConfAlias` + ", " + `client_cert` +  ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Modify an SSL Config Group
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminSSLConfig: modifySSLConfigGroup ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     scope                       "+confgrp_scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice ("     direction:                  "+direction)
    AdminUtilities.debugNotice (" SSL Config and cert:")
    AdminUtilities.debugNotice ("     SSL Config:                 "+sslConfAlias)
    AdminUtilities.debugNotice ("     SSL Config Scope:           "+sslConfScope)
    AdminUtilities.debugNotice ("     clientcert:                 "+client_cert)
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")
    
    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(confgrp_scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["confgrp_scope", confgrp_scope]))
    if (len(direction) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["direction", direction]))
    if (len(sslConfScope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["sslConfScope", sslConfScope]))
    if (len(sslConfAlias) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["sslConfAlias", sslConfAlias]))

    # Prepare the parameters for the AdminTask command:
    requiredParameters = [["name", name], ["scopeName", confgrp_scope], ["direction", direction], ["sslConfigScopeName", sslConfScope], ["sslConfigAliasName", sslConfAlias], ["certificateAlias", client_cert]]
    for attrs in requiredParameters:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr
    
    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(confgrp_scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Modify the SSL Config Group Alias
    AdminTask.modifySSLConfigGroup(finalParameters)

    # Save this SSL Config Group
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

# And now - modify the SSL Config Group in the target store.
modifySSLConfigGroup(confgrp_name, confgrp_scope, direction, ssl_conf_alias, ssl_conf_scope, c_cert)

END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
