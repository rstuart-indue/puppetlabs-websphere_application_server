# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_sslconfig).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create an SSL Config at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=tool-sslconfigcommands-command-group-admintask-object

    It is recommended to consult the IBM documentation as the SSL Config subject is reasonably complex.

    This provider will not allow the creation of a dummy instance - it requires valid keystores
    and truststores.

    This provider will not allow the changing of:
      * the name/alias of the SSL Config object
      * the type of the SSL Config object.
      * the JSSE provider 
    You need to destroy it first, then create another one with the desired attributes.

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

  # This creates the XOR string used in the authentication data entries.
  # For now, WAS8 and WAS9 are using the same schema of obfuscation for
  # the alias and KeyStore passwords.
  # The character used as the XOR key is "_" (underscore).
  def xor_string (val)
    xor_result = ""
    debase64 = Base64.decode64(val)

    debase64.each_char { |char|
      xor_result += (char.ord ^ "_".ord).ord.chr
    }
    return xor_result
  end

  def scope(what, target_scope: resource[:scope])
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"

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

  # Create an SSL Config Resource
  def create
    # Set the scope for this SSL ConfigResource.
     conf_scope = scope('xml')

    # At the very least - we pass the description of the Activation Specs.
    sslconfig_attrs = [
      ["type", "#{resource[:type]}"],
      ["jsseProvider", "#{resource[:jsse_provider]}"],
      ["clientAuthentication", "#{resource[:client_auth_req]}"],["clientAuthenticationSupported", "#{resource[:client_auth_supp]}"],                       ["securityLevel", "#{resource[:security_level]}"],
      ["enabledCyphers", "#{resource[:enabled_cyphers]}"],
      ["sslProtocol", "#{resource[:ssl_protocol]}"],
    ]

    # Add the scope names for the key and trust stores if they are different from the resource scope
    # If left unspecified, then the default resource scope is assumed.
    # The command will still fail if the keystore does not exist in that scope - which is OK, we want
    # it to fail.
    if resource[:key_store_scope] != resource[:scope]
      kstore_scope = scope('xml', target_scope: resource[:key_store_scope])
      sslconfig_attrs += [["keyStoreScopeName", "#{kstore_scope}"]]
    end

    if resource[:trust_store_scope] != resource[:scope]
      tstore_scope = scope('xml', target_scope: resource[:trust_store_scope])
      sslconfig_attrs += [["trustStoreScopeName", "#{tstore_scope}"]]
    end

    sslconfig_attrs_str = sslconfig_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our SSL Config
sslconfig_name = "#{resource[:conf_alias]}"
sslconfig_scope = "#{conf_scope}"
k_store = "#{resource[:key_store_name]}"
t_store = "#{resource[:trust_store_name]}"
t_cert = "#{resource[:client_cert_alias]}"
k_cert = "#{resource[:server_cert_alias]}"
sslconfig_attrs = #{sslconfig_attrs_str}

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

def createSSLConfig(name, conf_scope, key_store, trust_store, key_cert, trust_cert, sslConfigPList, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createSSLConfig(" + `name` +  ", " + `conf_scope`+ ", " + `trust_store` + ", " + `key_store` + ", " + `trust_cert` +  ", " + `key_cert` + `sslConfigPList` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create an SSL Config
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminSSLConfig: createSSLConfig ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     scope                       "+conf_scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" Trust and Key Stores:")
    AdminUtilities.debugNotice ("     keystore:                   "+key_store)
    AdminUtilities.debugNotice ("     truststore:                 "+trust_store)
    AdminUtilities.debugNotice ("     keycert:                    "+key_cert)
    AdminUtilities.debugNotice ("     trustcert:                  "+trust_cert)
    AdminUtilities.debugNotice (" SSL Config Options:")
    AdminUtilities.debugNotice ("     sslConfigPList:             "+str(sslConfigPList))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    sslConfigPList = normalizeArgList(sslConfigPList, "sslConfigPList")
    
    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(conf_scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["conf_scope", conf_scope]))
    if (len(trust_store) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["trust_store", trust_store]))
    if (len(key_store) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["key_store", key_store]))

    # Prepare the parameters for the AdminTask command:
    sslConfigPList = AdminUtilities.convertParamStringToList(sslConfigPList)
    requiredParameters = [["alias", name], ["scopeName", conf_scope], ["trustStoreName", trust_store], ["keyStoreName", key_store]]
    finalAttrsList = requiredParameters + sslConfigPList
    finalParameters = []
    for attrs in finalAttrsList:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr
    
    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(conf_scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Create the SSL Config Alias
    AdminTask.createSSLConfig(finalParameters)

    # Save this SSL Config
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

# And now - create the SSL Config in the target store.
createSSLConfig(sslconfig_name, sslconfig_scope, k_store, t_store, k_cert, t_cert, sslconfig_attrs)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create SSL Config alias: #{resource[:conf_alias]} for location #{resource[:key_store_name]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if an SSL Config exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:conf_alias]} from #{scope('file')}"
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

    # Note how "managementScope_1" is the attribute which ties the keyStores and SSL configs items to a managementScopes item.
    # Also, note how the references to the trust and keystores are done via the unique xmi:id identifiers.
    #
    # Aside to the fact that the managementScopes is there as a work-around for not having multiple security.xml files in
    # all the right places like we're having for the rest of the WAS settings
    #
    # So, with this said, what we have to do here is:
    #   * Find the appropriate management scope ID by working it back from the scope name (the XML one).
    #   * Find if we have an SSL config with the given name in that particular management scope ID
    #   * Extract the config details from the entry attributes if we do find one.
    #   * Reverse lookup the keystore details so that we can marry them up with the given params
    #   * Hope that the cert-alias clear-listing does not change in the future - as that's the only thing
    #     we can pick up without having to mangle it in the process.

    
    # Turns out that the SSL Config name has to be unique within the given management scope.
    mgmt_scope = XPath.first(sec_entry, "managementScopes[@scopeName='#{scope('xml')}']/@*[local-name()='id']") unless sec_entry.nil?
    debug "Found Management Scope entry for scope '#{resource[:scope]}': #{mgmt_scope.value.to_s}" unless mgmt_scope.nil?

    repertoire_entry = XPath.first(sec_entry, "repertoire[@managementScope='#{mgmt_scope.value.to_s}'][@alias='#{@resource[:conf_alias]}']") unless mgmt_scope.nil?

    debug "Found SSL Config entry for scope #{scope('xml')}: #{repertoire_entry}" unless repertoire_entry.nil?

    XPath.each(repertoire_entry, "setting/@*") { |attribute|
      attr_name = attribute.name.to_s
      attr_value = attribute.value.to_s
      case attr_name
      when 'keyStore', 'trustStore'
        # Reverse lookup the keyStore ID to what its real name is. Get the scope and scope-type while
        # we're here. Certainly don't want to regexp this thing later.
        kstore_name,kstore_mgtscope = XPath.match(sec_entry, "keyStores[@xmi:id='#{attr_value}']/@*[local-name()='name' or local-name()='managementScope']")
        kstore_scope,kstore_scope_type = XPath.match(sec_entry, "managementScopes[@xmi:id='#{kstore_mgtscope.value.to_s}']/@*[local-name()='scopeName' or local-name()='scopeType']")
        @old_conf_details[attr_name.to_sym] = kstore_name.value.to_s
        @old_conf_details["#{attr_name}Scope".to_sym] = kstore_scope.value.to_s
        @old_conf_details["#{attr_name}ScopeType".to_sym] = kstore_scope_type.value.to_s
      when 'keyManager', 'trustManager'
        # Reverse lookup the keyManager ID to what its real name is.
        # Ugh... this is bad. Turns out that key managers and trust managers can happily have the same name. In the
        # WebUI we end up with 3 items in the drop down list called "IBMX509" - which have different scopes but you
        # can't tell from looking at them which-is-which. I would wager that you won't know which is which when you
        # resolve them either - unless you have them in the management scope they are supposed to be. And this is all
        # from a clean install.
        #
        # This is really messed up! Thank you, you useless reptile.
        # Remember that the entries we're looking for are called "keyManagers" and "trustManagers" - plural,
        # therefore, note the "s" in the line immediately below, after the #{attr_name}
        mgr_name,mgr_mgtscope = XPath.match(sec_entry, "#{attr_name}s[@xmi:id='#{attr_value}']/@*[local-name()='name' or local-name()='managementScope']")
        mgr_scope,mgr_scope_type = XPath.match(sec_entry, "managementScopes[@xmi:id='#{mgr_mgtscope.value.to_s}']/@*[local-name()='scopeName' or local-name()='scopeType']")
        @old_conf_details[attr_name.to_sym] = mgr_name.value.to_s
        @old_conf_details["#{attr_name}Scope".to_sym] = mgr_scope.value.to_s
        @old_conf_details["#{attr_name}ScopeType".to_sym] = mgr_scope_type.value.to_s
      else
        @old_conf_details[attr_name.to_sym] = attr_value
      end    
    } unless repertoire_entry.nil?

    debug "SSL Config data for #{resource[:conf_alias]} is: #{@old_conf_details}"
    !repertoire_entry.nil?
  end

  def key_store_name
    @old_conf_details[:keyStoreName]
  end

  def key_store_name=(val)
    @property_flush[:keyStoreName] = val
  end

  def trust_store_name
    @old_conf_details[:trustStoreName]
  end

  def trust_store_name=(val)
    @property_flush[:trustStoreName] = val
  end

  def key_store_scope
    @old_conf_details[:keyStoreScopeType]
  end

  def key_store_scope=(val)
    @property_flush[:keyStoreScopeType] = val
  end

  def trust_store_scope
    @old_conf_details[:trustStoreScopeType]
  end

  def trust_store_scope=(val)
    @property_flush[:trustStoreScopeType] = val
  end

  def server_cert_alias
    @old_conf_details[:serverCertAlias]
  end

  def server_cert_alias=(val)
    @property_flush[:serverCertAlias] = val
  end

  def client_cert_alias
    @old_conf_details[:clientCertAlias]
  end

  def client_cert_alias=(val)
    @property_flush[:clientCertAlias] = val
  end

  def client_auth_req
    @old_conf_details[:clientAuthentication]
  end

  def client_auth_req=(val)
    @property_flush[:clientAuthentication] = val
  end

  def client_auth_supp
    @old_conf_details[:clientAuthenticationSupported]
  end

  def client_auth_supp=(val)
    @property_flush[:clientAuthenticationSupported] = val
  end

  def security_level
    @old_conf_details[:securityLevel]
  end

  def security_level=(val)
    @property_flush[:securityLevel] = val
  end

  def enabled_cyphers
    @old_conf_details[:enabledCiphers]
  end

  def enabled_cyphers=(val)
    @property_flush[:enabledCiphers] = val
  end

  def ssl_protocol
    @old_conf_details[:sslProtocol]
  end

  def ssl_protocol=(val)
    @property_flush[:sslProtocol] = val
  end

  # Remove a given SSL Config
  def destroy

    # Set the scope for this Keystore/SSLConfig.
    conf_scope = scope('xml')
    
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our SSLConfig removal
conf_scope = '#{conf_scope}'
config_alias = '#{resource[:conf_alias]}' 

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteSSLConfig(name, scope, ks_name, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteSSLConfig(" + `name` + ", " + `scope` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete an SSL Config
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminSSLConfig: deleteSSLConfig ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" SSL Config Alias:")
    AdminUtilities.debugNotice ("     name   :                    "+name)
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
    AdminUtilities.debugNotice("About to call AdminTask command for target SSL Config alias: " + str(name))

    # Delete the SSL Config Alias
    AdminTask.deleteSSLConfig(['-alias', name, '-scopeName', scope])

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
deleteSSLConfig(config_alias, conf_scope)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    cmd = <<-END.unindent
import AdminUtilities
import re

# TODO: flush() things in Jython
END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
