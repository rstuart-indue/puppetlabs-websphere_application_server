# frozen_string_literal: true

require 'base64'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_personalcert).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create an SSL Personal Certificate at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=tool-personalcertificatecommands-command-group-admintask-object

    It is recommended to consult the IBM documentation as the SSL Personal Certificate subject is reasonably complex.

    This provider will not allow the creation of a dummy instance.
    This provider will not allow the changing of:
      * the name of the Personal Certificate object.
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

  # Create a Personal Certificate Resource
  def create
    # Set the scope for this Certificate Resource.
    ks_scope = scope('xml') 

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our cert alias
cert_alias_dst = "#{resource[:cert_alias]}"
key_store_dst = "#{resource[:key_store_name]}"
key_store_scope = "#{ks_scope}"
key_file_src = "#{resource[:key_file_path]}"
key_file_type = "#{resource[:key_file_type]}"
key_file_pass = "#{resource[:key_file_pass]}"
cert_alias_src = "#{resource[:key_file_certalias]}"

# Certificate replacement variables
old_cert_name = "#{resource[:replace_old_cert]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def createPersonalCertAlias(name, kstore_scope, kstore_dst, kstore_src, kstore_type_src, kstore_pass_src, kstore_alias_src, old_cert='', failonerror=AdminUtilities._TRUE_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createPersonalCertAlias(" + `name` +  ", " + `kstore_scope`+ ", " + `kstore_dst` + ", " + `kstore_src` + ", " + `kstore_type_src` +  ", " + `kstore_alias_src` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a personal cert alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminPCertAlias: createPersonalCertAlias ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     keystore:                   "+kstore_dst)
    AdminUtilities.debugNotice ("     scope                       "+kstore_scope)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" Source:")
    AdminUtilities.debugNotice ("     type:                       "+kstore_type_src)
    AdminUtilities.debugNotice ("     keystore:                   "+kstore_src)
    AdminUtilities.debugNotice ("     alias:                      "+kstore_alias_src)
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
    if (len(kstore_src) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_src", kstore_src]))
    if (len(kstore_type_src) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_type_src", kstore_type_src]))
    if (len(kstore_pass_src) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_pass_src", kstore_pass_src]))
    if (len(kstore_alias_src) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["kstore_alias_src", kstore_alias_src]))

    # Prepare the parameters for the AdminTask command:
    finalParameters = ["-keyStoreScope", kstore_scope, "-certificateAlias", name, "-keyStoreName", kstore_dst, "-keyFilePath", kstore_src, "-keyFilePassword", kstore_pass_src, "-keyFileType", kstore_type_src, "-certificateAliasFromKeyFile", kstore_alias_src]

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with scope: " + str(kstore_scope))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalParameters))

    # Create the Personal Cert Alias by importing it from the source file
    AdminTask.importCertificate(finalParameters)

    # Now, see if we need to replace a cert
    if (len(old_cert) > 0):
      delete_old_cert = "#{resource[:delete_old_cert]}"
      delete_old_signers = "#{resource[:delete_old_signers]}"

      # Assemble the replace params
      replaceParameters = ["-keyStoreScope", kstore_scope, "-keyStoreName", kstore_dst, "-certificateAlias", old_cert, "-replacementCertificateAlias", name, "-deleteOldCert", delete_old_cert, "-deleteOldSigners", delete_old_signers]

      AdminUtilities.debugNotice("About to replace config references to old certificate: " + str(old_cert) + " with new certificate: " +str(name))
      # Replace the certificate
      AdminTask.replaceCertificate(replaceParameters)
    #endIf

    # Save this personal cert alias
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
createPersonalCertAlias(cert_alias_dst, key_store_scope, key_store_dst, key_file_src, key_file_type, key_file_pass, cert_alias_src, old_cert_name)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create personal certificate alias: #{resource[:cert_alias]} for location #{resource[:key_store_name]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Personal Certificate exists - must return a boolean.
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
    
    # Turns out that the Personal Certificate name has to be unique within the given management scope.
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

  # Remove a given Personal Certificate
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

def deletePersonalCertAlias(name, scope, ks_name, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deletePersonalCertAlias(" + `name` + ", " + `scope` + ", " + `ks_name`+ ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a personal cert alias
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminKS: deletePersonalCertAlias ")
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
    AdminTask.deleteCertificate(['-keyStoreName', ks_name, '-keyStoreScope', scope, '-certificateAlias', name])

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
deletePersonalCertAlias(certalias, ks_scope, keystore)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  # Since you can't change the params of a certificate after import, there's nothing
  # we need to do as flush(). The only way to modify a certificate is to delete it.
end
