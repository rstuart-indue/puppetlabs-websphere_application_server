# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_keystore).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create an SSL Keystore at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=tool-keystorecommands-command-group-admintask-object

    It is recommended to consult the IBM documentation as the SSL Keystore subject is reasonably complex.

    This provider will not allow the creation of a dummy instance.
    This provider will not allow the changing of:
      * the name of the Keystore object.
      * the type of a Keystore object.
      * the scope of a Keystore object.
      * the usage of a Keystore object.
      * the crypto hardware state
      * the remote host list
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
    @old_kstore_data = {}

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

  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"

    # I don't honestly know where the query/mod could be used, but sure as hell
    # the xml entry is used in security.xml scope attribute for a management scope.
    # It's yet another way of defining scope in WAS.
    case resource[:scope]
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
      xml   = "(cell):/#{resource[:cell]}:(node):#{resource[:node_name]}"
    when 'server'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/Server:#{resource[:server]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}"
      xml   = "(cell):#{resource[:cell]}:(node):#{resource[:node_name]}:(server):#{resource[:server]}"
    else
      raise Puppet::Error, "Unknown scope: #{resource[:scope]}"
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

  # Create a Keystore
  def create

    # Set the scope for this Keystore Resource.
    ks_scope = scope('xml') 

    # Pass the params to the keystore creation routine.
    ks_attrs = [["keyStoreDescription", "#{resource[:description]}"],
                ["keyStorePassword", "#{resource[:store_password]}"],
                ["keyStorePasswordVerify", "#{resource[:store_password]}"],
                ["keyStoreReadOnly", "#{resource[:readonly]}"],
                ["keyStoreInitAtStartup", "#{resource[:init_at_startup]}"],
                ["keyStoreHostList", "#{resource[:remote_hostlist]}"],
                ["enableCryptoOperations", "#{resource[:enable_crypto_hw]}"],
                ["keyStoreStashFile", "#{resource[:enable_stashfile]}"]]
    ks_attrs_str = ks_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our KeyStore
scope = '#{ks_scope}'
name = "#{resource[:ks_name]}"
location = "#{resource[:location]}"
type = "#{resource[:type]}"
usage = "#{resource[:usage]}"
ks_attrs = #{ks_attrs_str}

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

def createKeyStore(scope, name, location, dType, usage, ksList, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createKeyStore(" + `scope` +  ", " + `name`+ ", " + `location` + ", " + `dType` + ", " + `usage` +  ", " + `ksList` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a Key Store
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminKS: createKeyStore ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" Type:")
    AdminUtilities.debugNotice ("     type:                       "+dType)
    AdminUtilities.debugNotice (" Keystore main parameters:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice ("     location:                   "+location)
    AdminUtilities.debugNotice ("     usage              :        "+usage)
    AdminUtilities.debugNotice (" Keystore other parameters :")
    AdminUtilities.debugNotice ("   keystore attributes list:     "+str(ksList))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    ksList = normalizeArgList(ksList, "ksList")
    
    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(location) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["location", location]))
    if (len(dType) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["type", dType]))
    if (len(usage) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["usage", usage]))
    if (len(ksList) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["ksList", ksList]))

    # Prepare the parameters for the AdminTask command:
    ksList = AdminUtilities.convertParamStringToList(ksList)
    requiredParameters = [["scopeName", scope], ["keyStoreName", name], ["keyStoreLocation", location], ["keyStoreType", dType], ["keyStoreUsage", usage]]
    finalAttrsList = requiredParameters + ksList
    finalParameters = []
    for attrs in finalAttrsList:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Create the KeyStore
    AdminTask.createKeyStore(finalParameters)

    # Save this KeyStore
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

# And now - create the keystore
createKeyStore(scope, name, location, type, usage, ks_attrs)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Keystore: #{resource[:ks_name]} for location #{resource[:location]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Keystore exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:ks_name]} from #{scope('file')}"
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
    #  <managementScopes xmi:id="ManagementScope_1623648134948" scopeName="(cell):CELL_01:(node):NODE01" scopeType="node"/>
    #  <managementScopes xmi:id="ManagementScope_1623648150298" scopeName="(cell):CELL_01:(node):NODE02" scopeType="node"/>
    #  <keyStores xmi:id="KeyStore_1" name="CellDefaultKeyStore" password="{xor}XORRED_PASSWORD=" provider="IBMJCE" location="${CONFIG_ROOT}/cells/CELL_01/key.p12" type="PKCS12" fileBased="true" hostList="" description="Default key store for CELL_01" usage="SSLKeys" managementScope="ManagementScope_1"/>
    #  <keyStores xmi:id="KeyStore_2" name="CellDefaultTrustStore" password="{xor}XORRED_PASSWORD=" provider="IBMJCE" location="${CONFIG_ROOT}/cells/CELL_01/trust.p12" type="PKCS12" fileBased="true" hostList="" description="Default trust store for CELL_01" usage="SSLKeys" managementScope="ManagementScope_1"/>
    #  <keyStores xmi:id="KeyStore_3" name="CellLTPAKeys" password="{xor}XORRED_PASSWORD=" provider="IBMJCE" location="${CONFIG_ROOT}/cells/CELL_01/ltpa.jceks" type="JCEKS" fileBased="true" hostList="" description="LTPA key store for CELL_01" usage="KeySetKeys" managementScope="ManagementScope_1"/>
    #
    # Note how "managementScope_1" is the attribute which ties the keyStores item to a managementScopes item.
    #
    # Aside to the fact that the managementScopes is there as a work-around for not having multiple security.xml files in
    # all the right places like we're having for the rest of the WAS settings
    #
    # So, with this said, what we have to do here is:
    #   * Find the appropriate management scope ID by working it back from the scope name (the XML one).
    #   * Find if we have a keystore with the given name/path in that particular management scope ID
    #   * Extract the keystore details from the entry attributes if we do find one.
    
    # Turns out that the Keystore name has to be unique within the given management scope.
    mgmt_scope = XPath.first(sec_entry, "managementScopes[@scopeName='#{scope('xml')}']/@*[local-name()='id']") unless sec_entry.nil?
    debug "Found Management Scope entry for scope '#{resource[:scope]}': #{mgmt_scope.value.to_s}" unless mgmt_scope.nil?
    
    ks_entry = XPath.first(sec_entry, "keyStores[@managementScope='#{mgmt_scope.value.to_s}'][@name='#{@resource[:ks_name]}']") unless mgmt_scope.nil?
    debug "Found Keystore entry for scope #{scope('xml')}: #{ks_entry}" unless ks_entry.nil?

    XPath.each(ks_entry, "@*") { |attribute|
      @old_kstore_data[attribute.name.to_sym] = attribute.value.to_s
    } unless ks_entry.nil?
    
    debug "Exists? method result for #{resource[:ks_name]} is: #{ks_entry}"

    !ks_entry.nil?
  end

  # Get a Keystore's description
  def description
    @old_kstore_data[:description]
  end

  # Set a Keystore's description
  def description=(val)
    @property_flush[:description] = val
  end

  # Get a Keystore's usage
  def usage
    @old_kstore_data[:usage]
  end

  # Set a Keystore's usage
  def usage=(val)
    @property_flush[:usage] = val
  end

  # Get a Keystore's Type
  def type
    @old_kstore_data[:type]
  end

  # Set a Keystore's Type
  def type=(val)
    @property_flush[:type] = val
  end

  # Get a Keystore's destination location
  def location
    @old_kstore_data[:location]
  end

  # Set a Keystore's destination location
  def location=(val)
    @property_flush[:location] = val
  end

  # Get a Keystore's password - de-obfuscate it so we can compare them
  # At least we're not storing it de-obfuscated in memory. *sigh*
  def store_password
    stripped_pass = @old_kstore_data[:password].match(/^(?:{xor})(.*)/).captures.first

    old_pass = xor_string(stripped_pass)
    return old_pass
  end

  # Set a Keystore's password
  def store_password=(val)
    @property_flush[:password] = val
  end

  # Get a Keystore's initialize at startup status
  def init_at_startup
    @old_kstore_data.key?(:initializeAtStartup) ? @old_kstore_data[:initializeAtStartup] : :false
  end

  # Set a Keystore's initialize at startup status
  def init_at_startup=(val)
    @property_flush[:initializeAtStartup] = val
  end

  # Get a Keystore's readonly state
  def readonly
    @old_kstore_data.key?(:readOnly) ? @old_kstore_data[:readOnly] : :false
  end

  # Set a Keystore's readonly state
  def readonly=(val)
    @property_flush[:readOnly] = val
  end

  # Get a Keystore's Crypto HW status
  def enable_crypto_hw
    @old_kstore_data.key?(:useForAcceleration) ? @old_kstore_data[:useForAcceleration] : :false
  end

  # Set a Keystore's Crypto HW status
  def enable_crypto_hw=(val)
    raise Puppet::Error, "Hardware Crypto operations cannot be modified after the resource creation."
  end

  # Get a Keystore's remote host-list
  def remote_hostlist
    @old_kstore_data[:hostList]
  end

  # Set a Keystore's remote host-list
  def remote_hostlist=(val)
    raise Puppet::Error, "Remote host list cannot be modified after the resource creation."
  end

  # Remove a given Keystore
  def destroy

    # Set the scope for this Keystore.
    ks_scope = scope('xml')
    
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our KeyStore removal
scope = '#{ks_scope}'
name = "#{resource[:ks_name]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteKeyStore(scope, name, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteKeyStore(" + `scope` + ", " + `name`+ ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a Keystore
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminKS: deleteKeyStore ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" Key Store:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminTask command for target keystore: " + str(name))

    # Delete the KeyStore
    AdminTask.deleteKeyStore(['-keyStoreName', name, '-scopeName', scope])

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

# And now - delete the keystore
deleteKeyStore(scope, name)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?
    # Set the scope for this Keystore Resource.
    ks_scope = scope('xml') 

    # Check to see if we have to change the password for the store.
    if @property_flush.key?(:password)
      new_password = resource[:store_password]

      # de-obfuscate the old password
      stripped_pass = @old_kstore_data[:password].match(/^(?:{xor})(.*)/).captures.first
      current_password = xor_string(stripped_pass)
    else
      new_password = ''
      current_password = resource[:store_password]
    end

    # Pass the params to the keystore modification routine
    # Note that we will perform these changes first, then
    # if we need to, we change the password on the keystore.
    ks_attrs = [["keyStoreDescription", "#{resource[:description]}"],
                ["keyStorePassword", "#{current_password}"],
                ["keyStoreReadOnly", "#{resource[:readonly]}"],
                ["keyStoreInitAtStartup", "#{resource[:init_at_startup]}"]]
    ks_attrs_str = ks_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our KeyStore
scope = '#{ks_scope}'
name = "#{resource[:ks_name]}"
location = "#{resource[:location]}"
type = "#{resource[:type]}"
usage = "#{resource[:usage]}"
ks_attrs = #{ks_attrs_str}
new_password = '#{new_password}'

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

def modifyKeyStore(scope, name, location, dType, usage, ksList, newPass='', failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "modifyKeyStore(" + `scope` +  ", " + `name`+ ", " + `location` + ", " + `dType` + ", " + `usage` +  ", " + `ksList` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Modify a Key Store
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminKS: modifyKeyStore ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" Type:")
    AdminUtilities.debugNotice ("     type:                       "+dType)
    AdminUtilities.debugNotice (" Keystore main parameters:")
    AdminUtilities.debugNotice ("     name:                       "+name)
    AdminUtilities.debugNotice ("     location:                   "+location)
    AdminUtilities.debugNotice ("     usage              :        "+usage)
    AdminUtilities.debugNotice (" Keystore other parameters :")
    AdminUtilities.debugNotice ("   keystore attributes list:     "+str(ksList))
    AdminUtilities.debugNotice (" Keystore password change:")
    AdminUtilities.debugNotice ("   keystore new password:        "+str(newPass))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # This normalization is slightly superfluous, but, what the hey?
    ksList = normalizeArgList(ksList, "ksList")
    
    # Make sure required parameters are non-empty
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(location) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["location", location]))
    if (len(dType) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["type", dType]))
    if (len(usage) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["usage", usage]))
    if (len(ksList) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["ksList", ksList]))

    # Prepare the parameters for the AdminTask command:
    ksList = AdminUtilities.convertParamStringToList(ksList)
    requiredParameters = [["scopeName", scope], ["keyStoreName", name], ["keyStoreLocation", location], ["keyStoreType", dType], ["keyStoreUsage", usage]]
    finalAttrsList = requiredParameters + ksList
    finalParameters = []
    for attrs in finalAttrsList:
      attr = ["-"+attrs[0], attrs[1]]
      finalParameters = finalParameters+attr

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Modify the KeyStore
    AdminTask.modifyKeyStore(finalParameters)

    # If we have a new password specified - retrieve the old password and proceed to change it
    if (len(newPass) > 0):
      oldPass = ksList[1][1]
      AdminUtilities.debugNotice("About to change password on keystore with scope: " + str(scope))
      AdminUtilities.debugNotice("About to change password on keystore. Old pass: " + str(oldPass)) + "New pass: " + str(newPass)

      # We need the keystore name, the old pass, the new pass and optionally the scope name
      changePassParameters = [["-scopeName", scope], ["-keyStoreName", name], ["-keyStorePassword", oldPass], ["-newKeyStorePassword", newPass], ["-newKeyStorePasswordVerify", newPass]]

      # Change the password now
      AdminTask.changeKeyStorePassword(changePassParameters)
    # endIf

    # Save this KeyStore
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

# And now - modify the keystore
modifyKeyStore(scope, name, location, type, usage, ks_attrs, new_password)

END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
