# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_signercert).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create an SSL Signer Certificate at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=tool-signercertificatecommands-command-group-admintask-object

    It is recommended to consult the IBM documentation as the SSL Signer Certificate subject is reasonably complex.

    This provider will not allow the creation of a dummy instance.
    This provider will not allow the changing of:
      * the name of the Signer Certificate object.
      * the content of the Signer Certificate 
      * any other details of the Signer Certificate
    You need to destroy it first, then create another one with the desired attributes.

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  def initialize(val = {})
    super(val)
    @property_flush = {}

    @old_cert_details = {}

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
      xml   = "(cell):#{resource[:cell]}:(node):#{resource[:node_name]}"
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

  # Create a Signer Certificate Resource
  def create
    # Set the scope for this Certificate Resource.
    ks_scope = scope('xml') 

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our cert alias
cert_alias_dst = "#{resource[:cert_alias]}"
key_store_dst = "#{resource[:key_store_name]}"
key_store_scope = "#{ks_scope}"
cert_file_src = "#{resource[:cert_file_path]}"
is_base64 = "#{resource[:base_64_encoded]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def createSignerCertAlias(name, kstore_scope, kstore_dst, certfile_src, base64_encoded, old_cert='', failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createSignerCertAlias(" + `name` +  ", " + `kstore_scope`+ ", " + `kstore_dst` + ", " + `certfile_src` + ", " + `base64_encoded` +  ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a signer cert alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminPCertAlias: createSignerCertAlias ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     keystore:                   "+kstore_dst)
    AdminUtilities.debugNotice ("     scope                       "+kstore_scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" Source:")
    AdminUtilities.debugNotice ("     base64:                     "+base64_encoded)
    AdminUtilities.debugNotice ("     keystore:                   "+certfile_src)
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")
    
    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
      if (len(kstore_dst) == 0):
        raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_dst", kstore_dst]))
    if (len(kstore_scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_scope", kstore_scope]))
    if (len(certfile_src) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["certfile_src", certfile_src]))
    if (len(base64_encoded) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["base64_encoded", base64_encoded]))

    # Prepare the parameters for the AdminTask command:
    finalParameters = ["-keyStoreScope", kstore_scope, "-certificateAlias", name, "-keyStoreName", kstore_dst, "-certificateFilePath", certfile_src, "-base64Encoded", base64_encoded]

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(kstore_scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Create the Signer Cert Alias by importing it from the source file
    AdminTask.addSignerCertificate(finalParameters)

    # Save this signer cert alias
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

# And now - create the cert alias in the target store.
createSignerCertAlias(cert_alias_dst, key_store_scope, key_store_dst, cert_file_src, is_base64)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create signer certificate alias: #{resource[:cert_alias]} for location #{resource[:key_store_name]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Signer Certificate exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:cert_alias]} from #{scope('file')}"
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
    #   * Extract the certificate details from the keystore itself via the keytool helper

    
    # Turns out that the Signer Certificate name has to be unique within the given management scope.
    mgmt_scope = XPath.first(sec_entry, "managementScopes[@scopeName='#{scope('xml')}']/@*[local-name()='id']") unless sec_entry.nil?
    debug "Found Management Scope entry for scope '#{resource[:scope]}': #{mgmt_scope.value.to_s}" unless mgmt_scope.nil?

    ks_entry = XPath.first(sec_entry, "keyStores[@managementScope='#{mgmt_scope.value.to_s}'][@name='#{@resource[:key_store_name]}']") unless mgmt_scope.nil?

    debug "Found Keystore entry for scope #{scope('xml')}: #{ks_entry}" unless ks_entry.nil?

    kstore_data = {}
    XPath.each(ks_entry, "@*[local-name()='password' or local-name()='location' or local-name()='type']") { |attribute|
      case attribute.name.to_s
      when 'location'
        # We know if we get a ${CONFIG_ROOT} we have to replace that
        # with the whole path where the configs are. We only do the replacement
        # if the location starts with ${CONFIG_ROOT}
        kstore_data[attribute.name.to_sym] = attribute.value.to_s.sub(/^\$\{CONFIG_ROOT\}/, "#{resource[:profile_base]}/#{resource[:dmgr_profile]}/config")
      when 'password'
        # De-obfuscate the target keystore password
        # ... (or maybe should we pass that password in as an attribute?!)
        kstore_data[attribute.name.to_sym] = xor_string(attribute.value.to_s.match(/^(?:{xor})(.*)/).captures.first)
      else
        kstore_data[attribute.name.to_sym] = attribute.value.to_s
      end
    } unless ks_entry.nil?

    debug "KStore data for #{resource[:key_store_name]} is: #{kstore_data}"
    keytoolcmd = "-storetype #{kstore_data[:type]} -keystore #{kstore_data[:location]} -alias #{resource[:cert_alias]}"

    debug "Running keytool command with arguments: #{keytoolcmd} as user: #{resource[:user]}"
    result = keytool(passfile: kstore_data[:password], command: keytoolcmd, failonfail: false)
    debug result
  
    case result
    when %r{keytool error: java.lang.Exception: Alias <#{resource[:cert_alias]}> does not exist}
      return false
    when %r{keytool error: java.lang.Exception: Keystore file does not exist: #{kstore_data[:location]}}
      raise Puppet::Error, "Unable to open KeyStore file #{kstore_data[:location]}"
    when %r{Certificate fingerprint \(SHA1\):.*}
      # Remove any extra \n from the output. We really don't need them, so we replace with with spaces.
      @old_cert_details = result.tr("\n", ' ').match(/^(?<cert_name>\w+),\s+(?<expiry>\w+\s\d+,\s\w+),\s+(?<cert_type>\w+),\s+Certificate fingerprint\s+\(SHA1\):\s+(?<fingerprint>.*)/)
      debug "Found certificate alias: #{resource[:cert_alias]} with fingerprint: #{@cert_details}"
      return true
    else
      raise Puppet::Error, "An unexpected error has occured running keytool: #{result}"
    end

  end

  # Remove a given Signer Certificate
  def destroy

    # Set the scope for this Keystore/CertAlias.
    ks_scope = scope('xml')
    
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our CertAlias removal
ks_scope = '#{ks_scope}'
certalias = '#{resource[:cert_alias]}' 
keystore = "#{resource[:key_store_name]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteSignerCertAlias(name, scope, ks_name, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteSignerCertAlias(" + `name` + ", " + `scope` + ", " + `ks_name`+ ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a Certificate Alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminKS: deleteSignerCertAlias ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     scope:                      "+scope)
    AdminUtilities.debugNotice (" Key Store:")
    AdminUtilities.debugNotice ("     ks_name:                    "+ks_name)
    AdminUtilities.debugNotice (" Cert Alias:")
    AdminUtilities.debugNotice ("     name   :                    "+name)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(scope) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))
    if (len(ks_name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["ks_name", ks_name]))

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(scope))
    AdminUtilities.debugNotice("About to call AdminTask command for target certalias: " + str(name))

    # Delete the Cert Alias
    AdminTask.deleteSignerCertificate(['-keyStoreName', ks_name, '-keyStoreScope', scope, '-certificateAlias', name])

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
deleteSignerCertAlias(certalias, ks_scope, keystore)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  # If we have a nodename to sync to, let's call the super() method
  def flush
    if resource[:node_name].nil?
      return
    else
      super
    end
  end
end
