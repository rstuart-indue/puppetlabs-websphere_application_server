# frozen_string_literal: true

require_relative '../websphere_helper'

Puppet::Type.type(:websphere_jdbc_datasource).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
  Provider to manage or create a JDBC Data Source for a given JDBC provider at a specific scope.

  Please see the IBM documentation available at:
  https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-jdbcprovidermanagement-command-group-admintask-object

  It is recommended to consult the IBM documentation as the JDBC Provider and Data Source is reasonably complex

  This provider will not allow the creation of a dummy instance (i.e. no JDBC Provider)
  This provider will now allow the changing of:
    * the name of the Data Source
    * the type of a Data Source.
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
    @old_ds_data = {}
    @old_conn_pool_data = {}
    @old_mapping_data = {}
    @old_cmp_cf_data = {}
    @old_cmp_mapping_data = {}

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
    @xlate_cmd_table = {}

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

  def create

    # Set the scope for this JDBC Resource.
    jdbc_scope = scope('query')

    # Assemble the resource attributes pertaining to the DB connection
    case resource[:data_store_helper_class]
    when 'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
      resource_attrs = [['databaseName', 'java.lang.String', "#{resource[:database]}"],
                        ['driverType',   'java.lang.Integer', "#{resource[:db2_driver]}"],
                        ['serverName',   'java.lang.String', "#{resource[:db_server]}"],
                        ['portNumber',   'java.lang.Integer', "#{resource[:db_port]}"]]
    when 'com.ibm.websphere.rsadapter.MicrosoftSQLServerDataStoreHelper'
      resource_attrs = [['databaseName', 'java.lang.String', "#{resource[:database]}"],
                        ['serverName',   'java.lang.String', "#{resource[:db_server]}"],
                        ['portNumber',   'java.lang.Integer', "#{resource[:db_port]}"]]
    when 'com.ibm.websphere.rsadapter.Oracle11gDataStoreHelper'
      resource_attrs = [['URL', 'java.lang.String', "#{resource[:url]}"]]
    else
      raise Puppet::Error, "Unsupported Helper Class: #{resource[:data_store_helper_class]}"
    end
    resource_attrs_str = resource_attrs.to_s.tr("\"", "'")

    # Put the rest of the resource attributes together 
    extra_attrs = []
    extra_attrs += [['containerManagedPersistence',  "#{resource[:container_managed_persistence]}"]] unless resource[:container_managed_persistence].nil?
    extra_attrs += [['componentManagedAuthenticationAlias',  "#{resource[:component_managed_auth_alias]}"]] unless resource[:component_managed_auth_alias].nil?
    extra_attrs += [['xaRecoveryAuthAlias',  "#{resource[:xa_recovery_auth_alias]}"]] unless resource[:xa_recovery_auth_alias].nil?
    extra_attrs += [['description',  "#{resource[:description]}"]] unless resource[:description].nil?
    extra_attrs_str = extra_attrs.to_s.tr("\"", "'")

    # Make an nice array of arrays [[],[]] out of our hash, then turn into a simple string 
    # and convert double quotes to single quotes while we're at it
    cpool_attrs = []
    cpool_attrs = (resource[:conn_pool_data].map{|k,v| [k.to_s, v]}).to_a unless resource[:conn_pool_data].nil?
    cpool_attrs_str = cpool_attrs.to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our JDBC Data Source creation
scope = '#{jdbc_scope}'
ds_helper = "#{resource[:data_store_helper_class]}"
ds_name = "#{resource[:ds_name]}"
jndi_name = "#{resource[:jndi_name]}"
provider = "#{resource[:jdbc_provider]}"
cpool_attrs = #{cpool_attrs_str}

resource_attrs = #{resource_attrs_str}
extra_attrs = #{extra_attrs_str}

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

def createDataSourceAtScope( scope, JDBCProvider, datasourceName, jndiName, dataStoreHelperClassName, otherAttrsList=[], resourceAttrsList=[], connectionPoolAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
    if(failonerror==AdminUtilities._BLANK_):
        failonerror=AdminUtilities._FAIL_ON_ERROR_
    #endIf
    msgPrefix = "createDataSourceAtScope("+`scope`+", "+`JDBCProvider`+", "+`datasourceName`+", "+`jndiName`+", "+`dataStoreHelperClassName`+", "+`otherAttrsList`+", "+`resourceAttrsList`+", "+`connectionPoolAttrsList`+", ` "+`failonerror`+"): "

    try:
        #--------------------------------------------------------------------
        # Create JDBC DataSource
        #--------------------------------------------------------------------
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" AdminJDBC:                  create JDBC DataSource")
        AdminUtilities.debugNotice (" Scope:")
        AdminUtilities.debugNotice ("    scope                                   "+scope)
        AdminUtilities.debugNotice (" JDBC provider:")
        AdminUtilities.debugNotice ("    name                                    "+JDBCProvider)
        AdminUtilities.debugNotice (" DataSource:")
        AdminUtilities.debugNotice ("    name                                    "+datasourceName)
        AdminUtilities.debugNotice ("    jndiName                                "+jndiName)
        AdminUtilities.debugNotice ("    dataStoreHelperClassName                "+dataStoreHelperClassName)
        AdminUtilities.debugNotice (" Additional attributes:")
        AdminUtilities.debugNotice ("    otherAttributesList:                    "+str(otherAttrsList))
        AdminUtilities.debugNotice ("    ResourceAttributesList:                 "+str(resourceAttrsList))
        AdminUtilities.debugNotice ("    ConnectionPoolAttributesList:           "+str(connectionPoolAttrsList))        
        AdminUtilities.debugNotice (" Return: The configuration ID of the new JDBC data source")
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" ")

        # This normalization is slightly superfluous, but, what the hey?
        otherAttrsList = normalizeArgList(otherAttrsList, "otherAttrsList")
        resourceAttrsList = normalizeArgList(resourceAttrsList, "resourceAttrsList")
        connectionPoolAttrsList = normalizeArgList(connectionPoolAttrsList, "connectionPoolAttrsList")

        # Checking that the passed in parameters are not empty
        # WASL6041E=WASL6041E: Invalid parameter value: {0}:{1}
        if (len(scope) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))

        if (len(JDBCProvider) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["JDBCProvider", JDBCProvider]))

        if (len(datasourceName) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["datasourceName", datasourceName]))

        if (len(jndiName) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["jndiName", jndiName]))

        if (len(dataStoreHelperClassName) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["dataStoreHelperClassName", dataStoreHelperClassName]))

        if (len(scope) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

        # Get the ID for the supplied JDBCProvider
        jdbcProvId = AdminConfig.getid(scope+"/JDBCProvider:"+JDBCProvider)
        if (len(jdbcProvId) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["JDBCProvider", JDBCProvider]))

        #prepare for AdminTask command call
        requiredParameters = [["name", datasourceName],["jndiName", jndiName],["dataStoreHelperClassName", dataStoreHelperClassName]]

        # Convert to list
        otherAttrsList = AdminUtilities.convertParamStringToList(otherAttrsList)
        resourceAttrsList = AdminUtilities.convertParamStringToList(resourceAttrsList)
        connectionPoolAttrsList = AdminUtilities.convertParamStringToList(connectionPoolAttrsList)

        finalAttrsList = requiredParameters + otherAttrsList

        # Assemble all the command parameters
        finalParamList = []
        for attrs in finalAttrsList:
          attr = ["-"+attrs[0], attrs[1]]
          finalParamList = finalParamList + attr

        # The -configureResourceProperties takes a mangled array of arrays with no commas
        resPropList = ['-configureResourceProperties', str(resourceAttrsList).replace(',', '')]

        finalParameters = []
        finalParameters = finalParamList + resPropList

        AdminUtilities.debugNotice("Creating datasource for JDBC Provider ID %s  with args %s" %(jdbcProvId, str(finalParameters)))

        # Create the JDBC Datasource for the given JDBC Provider
        newObjectId = AdminTask.createDatasource(jdbcProvId, finalParameters )

        # Set the Connection Pool Params - the modify() takes a mangled array of arrays with no commas
        if connectionPoolAttrsList:
          connectionPool = AdminConfig.showAttribute(newObjectId, 'connectionPool')
          AdminConfig.modify(connectionPool, str(connectionPoolAttrsList).replace(',', ''))

        # Save this JDBC DataSource
        AdminConfig.save()
        return str(newObjectId)

    except:
        typ, val, tb = sys.exc_info()
        if(typ==SystemExit):  raise SystemExit,`val`
        if (failonerror != AdminUtilities._TRUE_):
            print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
            val = "%s %s" % (sys.exc_type, sys.exc_value)
            raise Exception("ScriptLibraryException: " + val)
        else:
             return AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
        #endIf
    #endTry
    AdminUtilities.infoNotice(AdminUtilities._OK_+msgPrefix)
#endDef

# And now - create the JDBC Data Source
createDataSourceAtScope(scope, provider, ds_name, jndi_name, ds_helper, extra_attrs, resource_attrs, cpool_attrs)

END
    # rubocop:enable Layout/IndentHeredoc

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)
    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create JDBC Data Source: #{resource[:ds_name]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end
    debug "Result:\n#{result}"
  end

  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    doc = REXML::Document.new(File.open(scope('file')))

    debug "Retrieving value of #{resource[:jdbc_provider]}/#{resource[:ds_name]} from #{scope('file')}"

        # We're looking for Connection Factory entries matching our cf_name. We have to ensure we're looking under the
    # correct provider entry.
    provider_entry = XPath.first(doc, "/xmi:XMI[@xmlns:resources.jdbc]/resources.jdbc:JDBCProvider[@name='#{resource[:jdbc_provider]}']")
    ds_entry = XPath.first(provider_entry, "factories[@xmi:type='resources.jdbc:DataSource'][@name='#{resource[:ds_name]}']") unless provider_entry.nil?

    # Populate the @old_ds_data by discovering what are the params for the given DataSource
    debug "Exists? method is loading existing Data Source data attributes/values:"
    XPath.each(ds_entry, "@*")  { |attr|
      debug "#{attr.name} => #{attr.value}"
      xlated_name = @xlate_cmd_table.key?(attr.name) ? @xlate_cmd_table[attr.name] : attr.name
      @old_ds_data[xlated_name.to_sym] = attr.value
    } unless ds_entry.nil?

    # Extract the connectionPool attributes
    XPath.each(ds_entry, "connectionPool/@*")  { |attr|
      debug "#{attr.name} => #{attr.value}"
      @old_conn_pool_data[attr.name.to_sym] = attr.value
    } unless ds_entry.nil?

    # Extract the Auth mapping attributes
    XPath.each(ds_entry, "mapping/@*")  { |attr|
      debug "#{attr.name} => #{attr.value}"
      @old_mapping_data[attr.name.to_sym] = attr.value
    } unless ds_entry.nil?

    # Extract the Oracle DB URL value for the resource. It will either be an URL or an empty string.
    oradb_url = XPath.first(ds_entry, "propertySet/resourceProperties[@name='URL']/@*[local-name()='value']") unless ds_entry.nil?
    @old_ds_data[:url] = oradb_url.value.to_s unless oradb_url.nil?

    debug "Exists? method result for #{resource[:ds_name]} is: #{ds_entry.nil?}"

    !ds_entry.nil?
  end

  # Get the component-managed authentication alias
  def component_managed_auth_alias
    @old_ds_data[:authDataAlias]
  end

  # Set the component-managed authentication alias
  def component_managed_auth_alias=(val)
    @property_flush[:authDataAlias] = val
  end

    # Get the XA recovery authentication alias
  def xa_recovery_auth_alias
    @old_ds_data[:xaRecoveryAuthAlias]
  end

  # Set the XA recovery authentication alias
  def xa_recovery_auth_alias=(val)
    @property_flush[:xaRecoveryAuthAlias] = val
  end

  # Get the mapping configuration alias
  def mapping_configuration_alias
    @old_mapping_data[:mappingConfigAlias]
  end

  # Set the mapping configuration alias
  def mapping_configuration_alias=(val)
    @property_flush[:mappingConfigAlias] = val
  end

  # Get the container-managed authentication alias
  def container_managed_auth_alias
    @old_mapping_data[:authDataAlias]
  end

  # Set the container-managed authentication alias
  def container_managed_auth_alias=(val)
    @property_flush[:mappingAuthDataAlias] = val
  end

  # Get the connection pool data
  def conn_pool_data
    @old_conn_pool_data
  end

  # Set the connection pool data
  def conn_pool_data=(val)
    @property_flush[:connectionPoolData] = val
  end

  # Get the Oracle DB URL
  def url
    @old_ds_data[:url]
  end

  # Set the Oracle DB URL
  def url=(val)
    @property_flush[:url] = val
  end

  def destroy
    # AdminTask.deleteJDBCProvider('(cells/CELL_01|resources.xml#JDBCProvider_1422560538842)')
    Puppet.warning('Removal of JDBC Providers is not yet implemented')
  end

  def flush
    case resource[:scope]
    when %r{(server|node)}
      sync_node
    end
  end
end
