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
    extra_attrs += [['containerManagedPersistence',  "#{resource[:container_managed_persistence]}"]]
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

map_alias = '#{resource[:mapping_configuration_alias]}'
container_auth_alias = '#{resource[:container_managed_auth_alias]}'
component_auth_alias = '#{resource[:component_managed_auth_alias]}'
xa_recovery_auth_alias = '#{resource[:xa_recovery_auth_alias]}'

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

# Get the ObjectID of a named object, of a given type at a specified scope.
def getObjectId (scope, objectType, objName):
    objId = AdminConfig.getid(scope+"/"+objectType+":"+objName)
    return objId
#endDef

def createDataSourceAtScope( scope, JDBCProvider, datasourceName, jndiName, dataStoreHelperClassName, mappingConfigAlias='', authDataAlias='', xaRecoveryAuthAlias='', componentAuthAlias='', otherAttrsList=[], resourceAttrsList=[], connectionPoolAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
    if(failonerror==AdminUtilities._BLANK_):
        failonerror=AdminUtilities._FAIL_ON_ERROR_
    #endIf
    msgPrefix = "createDataSourceAtScope("+`scope`+", "+`JDBCProvider`+", "+`datasourceName`+", "+`jndiName`+", "+`dataStoreHelperClassName`+", "+`otherAttrsList`+", "+`resourceAttrsList`+", "+`connectionPoolAttrsList`+", "+`failonerror`+"): "

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
        AdminUtilities.debugNotice (" Security attributes:")
        AdminUtilities.debugNotice ("    componentAuthAlias:                     "+componentAuthAlias)
        AdminUtilities.debugNotice ("    xaRecoveryAuthAlias:                    "+xaRecoveryAuthAlias)
        AdminUtilities.debugNotice ("    mappingConfigAlias:                     "+mappingConfigAlias)
        AdminUtilities.debugNotice ("    authDataAlias:                          "+authDataAlias)
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

        # Get the JDBC Provider ID so that we can find its providerType attribute.
        jdbcProviderId = getObjectId(scope, 'JDBCProvider', JDBCProvider)
        if (len(jdbcProviderId) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["JDBCProvider", JDBCProvider]))

        #prepare for AdminTask command call
        requiredParameters = [["name", datasourceName],["jndiName", jndiName],["dataStoreHelperClassName", dataStoreHelperClassName]]

        # Convert to list
        otherAttrsList = AdminUtilities.convertParamStringToList(otherAttrsList)
        resourceAttrsList = AdminUtilities.convertParamStringToList(resourceAttrsList)
        connectionPoolAttrsList = AdminUtilities.convertParamStringToList(connectionPoolAttrsList)

        finalAttrsList = requiredParameters + otherAttrsList + [['componentManagedAuthenticationAlias', componentAuthAlias]]

        # Set the xaRecoveryAuthAlias attribute if the JDBC Provider is an XA type
        AdminUtilities.debugNotice("JDBC Provider ID: %s" % (jdbcProviderId))
        jdbcProviderType = AdminConfig.showAttribute(jdbcProviderId, 'providerType')
        AdminUtilities.debugNotice("JDBC Provider Type: %s" % (jdbcProviderType))
        if jdbcProviderType:
          if jdbcProviderType.find("XA") >= 0 and xaRecoveryAuthAlias:
              finalAttrsList.append(['xaRecoveryAuthAlias', xaRecoveryAuthAlias])
          #endIf
        #endIf

        # Assemble all the command parameters
        finalParamList = []
        for attrs in finalAttrsList:
          attr = ["-"+attrs[0], attrs[1]]
          finalParamList = finalParamList + attr

        finalParameters = []

        # The -configureResourceProperties takes a mangled array of arrays with no commas
        resPropList = ['-configureResourceProperties', str(resourceAttrsList).replace(',', '')]

        finalParameters = finalParamList + resPropList

        AdminUtilities.debugNotice("Creating datasource for JDBC Provider ID %s  with args %s" %(jdbcProviderId, str(finalParameters)))

        # Create the JDBC Datasource for the given JDBC Provider
        newObjectId = AdminTask.createDatasource(jdbcProviderId, finalParameters )
        mapModuleData = [['mappingConfigAlias', mappingConfigAlias], ['authDataAlias', authDataAlias]]
        AdminConfig.create('MappingModule', newObjectId, str(mapModuleData).replace(',', ''))

        # Get the Container Managed Persistence (CMP) Connector Factory ID. Its name is derived from the Data Source name it
        # belongs to and the '_CF' suffix.
        CMPConnFactoryId = getObjectId(scope, 'J2CResourceAdapter:WebSphere Relational Resource Adapter/CMPConnectorFactory', datasourceName+'_CF')

        AdminUtilities.debugNotice("CMP Connection Factory ID: %s" % (CMPConnFactoryId))
        # Configure the mapping config alias and auth data alias
        if CMPConnFactoryId:
          cmpCFData = [['name', datasourceName+"_CF"], ['authDataAlias', authDataAlias]]
          if jdbcProviderType:
            if jdbcProviderType.find("XA") >= 0 and xaRecoveryAuthAlias:
              cmpCFData.append(['xaRecoveryAuthAlias', xaRecoveryAuthAlias])
            #endIf
          #endIf
          AdminConfig.modify(CMPConnFactoryId, str(cmpCFData).replace(',', ''))
          AdminConfig.create('MappingModule', CMPConnFactoryId, str(mapModuleData).replace(',', ''))

        # Set the Connection Pool Params - the modify() takes a mangled array of arrays with no commas
        if connectionPoolAttrsList:
          connectionPool = AdminConfig.showAttribute(newObjectId, 'connectionPool')
          AdminUtilities.debugNotice("Connection Pool ID: %s" % (connectionPool))
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
createDataSourceAtScope(scope, provider, ds_name, jndi_name, ds_helper, map_alias, container_auth_alias, xa_recovery_auth_alias, component_auth_alias, extra_attrs, resource_attrs, cpool_attrs)


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
    # Set the scope for this JDBC Resource.
    jdbc_scope = scope('query')
    cmd = <<-END.unindent
import AdminUtilities
import re

# Parameters we need for our JDBC Data Source modification
scope = '#{jdbc_scope}'

ds_name = "#{resource[:ds_name]}"

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

# Get the ObjectID of a named object, of a given type at a specified scope.
def getObjectId (scope, objectType, objName):
    objId = AdminConfig.getid(scope+"/"+objectType+":"+objName)
    return objId
#endDef

def deleteDataSourceAtScope( scope, datasourceName, failonerror=AdminUtilities._BLANK_ ):
    if(failonerror==AdminUtilities._BLANK_):
        failonerror=AdminUtilities._FAIL_ON_ERROR_
    #endIf
    msgPrefix = "deleteDataSourceAtScope("+`scope`+", "+`datasourceName`+", "+`failonerror`+"): "

    try:
        #--------------------------------------------------------------------
        # Delete JDBC DataSource
        #--------------------------------------------------------------------
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" AdminJDBC:                  modify JDBC DataSource")
        AdminUtilities.debugNotice (" Scope:")
        AdminUtilities.debugNotice ("    scope                                   "+scope)
        AdminUtilities.debugNotice (" DataSource:")
        AdminUtilities.debugNotice ("    name                                    "+datasourceName)
        AdminUtilities.debugNotice (" Return: NULL")
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" ")

        # Checking that the passed in parameters are not empty
        # WASL6041E=WASL6041E: Invalid parameter value: {0}:{1}
        if (len(scope) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["scope", scope]))

        if (len(datasourceName) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["datasourceName", datasourceName]))

        # Get the JDBC Datasource for the given name
        # Whilst scoped resources, you cannot specify the scope when you are looking them up
        # So you always look them up as follows: AdminConfig.getid('/DataSource:<datasource_name_blah_ds>/')
        # or, as is the case of the getObjectId() method, set the `scope` argument to the empty string ''
        dataSourceId = getObjectId('', 'DataSource', datasourceName)
        AdminUtilities.debugNotice("Deleting DataSource ID %s" %(dataSourceId))

        # Get the Container Managed Persistence (CMP) Connector Factory ID. Its name is derived from the Data Source name it
        # belongs to and the '_CF' suffix.
        CMPConnFactoryId = getObjectId(scope, 'J2CResourceAdapter:WebSphere Relational Resource Adapter/CMPConnectorFactory', datasourceName+'_CF')
        AdminUtilities.debugNotice("CMP Connection Factory ID: %s" % (CMPConnFactoryId))
        if CMPConnFactoryId:
          AdminConfig.remove(CMPConnFactoryId)

        # Remove the DataSource itself now
        AdminConfig.remove(dataSourceId)

        # Save these changes
        AdminConfig.save()
        return

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

# And now - Delete the JDBC Data Source
deleteDataSourceAtScope(scope, ds_name)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)
    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      err = <<-EOT
      Could not delete JDBC Data Source: #{resource[:ds_name]}
      EOT
      raise Puppet::Error, err
    end
    debug "Result:\n#{result}"
  end

  def flush

    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    # Set the scope for this JDBC Resource.
    jdbc_scope = scope('query')

    # Assemble the resource attributes pertaining to the DB connection
    case resource[:data_store_helper_class]
    when 'com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper'
      resource_attrs = [[['name', 'databaseName'], ['type', 'java.lang.String'], ['value', "#{resource[:database]}"]],
                        [['name', 'driverType'], ['type', 'java.lang.Integer'], ['value', "#{resource[:db2_driver]}"]],
                        [['name', 'serverName'], ['type', 'java.lang.String'], ['value', "#{resource[:db_server]}"]],
                        [['name', 'portNumber'], ['type', 'java.lang.Integer'], ['value', "#{resource[:db_port]}"]]]
    when 'com.ibm.websphere.rsadapter.MicrosoftSQLServerDataStoreHelper'
      resource_attrs = [[['name', 'databaseName'], ['type', 'java.lang.String'], ['value', "#{resource[:database]}"]],
                        [['name', 'serverName'], ['type', 'java.lang.String'], ['value', "#{resource[:db_server]}"]],
                        [['name', 'portNumber'], ['type', 'java.lang.Integer'], ['value', "#{resource[:db_port]}"]]]
    when 'com.ibm.websphere.rsadapter.Oracle11gDataStoreHelper'
      resource_attrs = [[['name', 'URL'], ['type', 'java.lang.String'], ['value', "#{resource[:url]}"]]]
    else
      raise Puppet::Error, "Unsupported Helper Class: #{resource[:data_store_helper_class]}"
    end
    resource_attrs_str = resource_attrs.to_s.tr("\"", "'")

    # Put the rest of the resource attributes together 
    extra_attrs = []
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

# Parameters we need for our JDBC Data Source modification
scope = '#{jdbc_scope}'
ds_helper = "#{resource[:data_store_helper_class]}"
ds_name = "#{resource[:ds_name]}"
jndi_name = "#{resource[:jndi_name]}"
provider = "#{resource[:jdbc_provider]}"
cpool_attrs = #{cpool_attrs_str}

resource_attrs = #{resource_attrs_str}
extra_attrs = #{extra_attrs_str}

map_alias = '#{resource[:mapping_configuration_alias]}'
container_auth_alias = '#{resource[:container_managed_auth_alias]}'
component_auth_alias = '#{resource[:component_managed_auth_alias]}'
xa_recovery_auth_alias = '#{resource[:xa_recovery_auth_alias]}'

cmp_enabled = '#{resource[:container_managed_persistence]}'

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

# Get the ObjectID of a named object, of a given type at a specified scope.
def getObjectId (scope, objectType, objName):
    objId = AdminConfig.getid(scope+"/"+objectType+":"+objName)
    return objId
#endDef

def modifyDataSourceAtScope( scope, JDBCProvider, datasourceName, jndiName, cmpEnabled, dataStoreHelperClassName, mappingConfigAlias='', authDataAlias='', xaRecoveryAuthAlias='', componentAuthAlias='', otherAttrsList=[], resourceAttrsList=[], connectionPoolAttrsList=[], failonerror=AdminUtilities._BLANK_ ):
    if(failonerror==AdminUtilities._BLANK_):
        failonerror=AdminUtilities._FAIL_ON_ERROR_
    #endIf
    msgPrefix = "modifyDataSourceAtScope("+`scope`+", "+`JDBCProvider`+", "+`datasourceName`+", "+`jndiName`+", "+`cmpEnabled`+", "+`dataStoreHelperClassName`+", "+`otherAttrsList`+", "+`resourceAttrsList`+", "+`connectionPoolAttrsList`+", "+`failonerror`+"): "

    try:
        #--------------------------------------------------------------------
        # Modify JDBC DataSource
        #--------------------------------------------------------------------
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" AdminJDBC:                  modify JDBC DataSource")
        AdminUtilities.debugNotice (" Scope:")
        AdminUtilities.debugNotice ("    scope                                   "+scope)
        AdminUtilities.debugNotice (" JDBC provider:")
        AdminUtilities.debugNotice ("    name                                    "+JDBCProvider)
        AdminUtilities.debugNotice (" DataSource:")
        AdminUtilities.debugNotice ("    name                                    "+datasourceName)
        AdminUtilities.debugNotice ("    jndiName                                "+jndiName)
        AdminUtilities.debugNotice ("    CMP Enabled                             "+cmpEnabled)
        AdminUtilities.debugNotice ("    dataStoreHelperClassName                "+dataStoreHelperClassName)
        AdminUtilities.debugNotice (" Security attributes:")
        AdminUtilities.debugNotice ("    componentAuthAlias:                     "+componentAuthAlias)
        AdminUtilities.debugNotice ("    xaRecoveryAuthAlias:                    "+xaRecoveryAuthAlias)
        AdminUtilities.debugNotice ("    mappingConfigAlias:                     "+mappingConfigAlias)
        AdminUtilities.debugNotice ("    authDataAlias:                          "+authDataAlias)
        AdminUtilities.debugNotice (" Additional attributes:")
        AdminUtilities.debugNotice ("    otherAttributesList:                    "+str(otherAttrsList))
        AdminUtilities.debugNotice ("    ResourceAttributesList:                 "+str(resourceAttrsList))
        AdminUtilities.debugNotice ("    ConnectionPoolAttributesList:           "+str(connectionPoolAttrsList))
        AdminUtilities.debugNotice (" Return: NULL")
        AdminUtilities.debugNotice ("---------------------------------------------------------------")
        AdminUtilities.debugNotice (" ")

        # This normalization is slightly superfluous, but, what the hey?
        otherAttrsList = normalizeArgList(otherAttrsList, "otherAttrsList")
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

        if (len(cmpEnabled) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["cmpEnabled", cmpEnabled]))

        if (len(dataStoreHelperClassName) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["dataStoreHelperClassName", dataStoreHelperClassName]))

        if (len(scope) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["scope", scope]))

        # Get the JDBC Provider ID so that we can find its providerType attribute.
        jdbcProviderId = getObjectId(scope, 'JDBCProvider', JDBCProvider)
        if (len(jdbcProviderId) == 0):
            raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6040E", ["JDBCProvider", JDBCProvider]))

        # Prepare for AdminTask command call
        # Remember that when modifying the resource - the param names are inconsistent: "dataStoreHelperClassName" is actually
        # "datasourceHelperClassname"
        requiredParameters = [["name", datasourceName],["jndiName", jndiName],["datasourceHelperClassname", dataStoreHelperClassName]]

        # Convert to list
        otherAttrsList = AdminUtilities.convertParamStringToList(otherAttrsList)
        resourceAttrsList = AdminUtilities.convertParamStringToList(resourceAttrsList)
        connectionPoolAttrsList = AdminUtilities.convertParamStringToList(connectionPoolAttrsList)

        # Assemble all the command parameters
        # ... and componentManagedAuthenticationAlias is no longer used, instead authDataAlias is used in its place
        finalAttrsList = requiredParameters + otherAttrsList + [['authDataAlias', componentAuthAlias]]

        # Set the xaRecoveryAuthAlias attribute if the JDBC Provider is an XA type
        AdminUtilities.debugNotice("JDBC Provider ID: %s" % (jdbcProviderId))
        jdbcProviderType = AdminConfig.showAttribute(jdbcProviderId, 'providerType')
        AdminUtilities.debugNotice("JDBC Provider Type: %s" % (jdbcProviderType))
        if jdbcProviderType:
          if jdbcProviderType.find("XA") >= 0 and xaRecoveryAuthAlias:
              finalAttrsList.append(['xaRecoveryAuthAlias', xaRecoveryAuthAlias])
          #endIf
        #endIf

        # Get the JDBC Datasource for the given name
        # Whilst scoped resources, you cannot specify the scope when you are looking them up
        # So you always look them up as follows: AdminConfig.getid('/DataSource:<datasource_name_blah_ds>/')
        # or, as is the case of the getObjectId() method, set the `scope` argument to the empty string ''
        dataSourceId = getObjectId('', 'DataSource', datasourceName)
        AdminUtilities.debugNotice("Modifying DataSource ID %s for JDBC Provider ID %s  with args %s" %(dataSourceId, jdbcProviderId, str(finalAttrsList)))

        # Get the Container Managed Persistence (CMP) Connector Factory ID. Its name is derived from the Data Source name it
        # belongs to and the '_CF' suffix.
        CMPConnFactoryId = getObjectId(scope, 'J2CResourceAdapter:WebSphere Relational Resource Adapter/CMPConnectorFactory', datasourceName+'_CF')
        AdminUtilities.debugNotice("CMP Connection Factory ID: %s" % (CMPConnFactoryId))

        mapModuleData = [['mappingConfigAlias', mappingConfigAlias], ['authDataAlias', authDataAlias]]
        # Manage the CMP existence
        if cmpEnabled == 'false':
          if CMPConnFactoryId:
            AdminConfig.remove(CMPConnFactoryId)
        else:
          cmpCFData = [['name', datasourceName+"_CF"], ['authDataAlias', authDataAlias]]
          if jdbcProviderType:
            if jdbcProviderType.find("XA") >= 0 and xaRecoveryAuthAlias:
              cmpCFData.append(['xaRecoveryAuthAlias', xaRecoveryAuthAlias])
            #endIf
          #endIf
          # Configure the mapping config alias and auth data alias
          if CMPConnFactoryId:
            cmpMappingModuleId = AdminConfig.showAttribute(CMPConnFactoryId, 'mapping')
            AdminConfig.modify(CMPConnFactoryId, str(cmpCFData).replace(',', ''))
            AdminConfig.modify(cmpMappingModuleId, str(mapModuleData).replace(',', ''))
          else:
            # We have to create the CMP Connector Factory from scratch. Which means we have to set up
            cmpCreateData = []
            cmpCreateData.append ( ["name", datasourceName+'_CF'] )
            cmpCreateData.append ( ["authMechanismPreference", "BASIC_PASSWORD"] )
            cmpCreateData.append ( ["cmpDatasource", str(dataSourceId)] )

            rraId = getObjectId(scope, 'J2CResourceAdapter', 'WebSphere Relational Resource Adapter')
            CMPConnFactoryId = AdminConfig.create('CMPConnectorFactory', rraId, str(cmpCreateData).replace(',', ''))
            AdminConfig.modify(CMPConnFactoryId, str(cmpCFData).replace(',', ''))
            AdminConfig.create('MappingModule', CMPConnFactoryId, str(mapModuleData).replace(',', ''))
          #endIf

        # Update the DataSource itself now
        AdminConfig.modify(dataSourceId, str(finalAttrsList).replace(',', ''))

        # Update the DB Attributes now. What we get is a collection (array of arrays) in the
        # form of:
        # [[[name "databaseName"] [type "java.lang.String"] [value "DBNAME"]]
        #  [[name "serverName"] [type "java.lang.String"] [value "foo.bar.baz.com"]]
        #  [[name "portNumber"] [type "java.lang.String"] [value "1653"]]]
        # So to get the name of the attribute to update, we have to get the second element of the first array.
        dsScope = '/JDBCProvider:'+JDBCProvider+'/DataSource:'+datasourceName
        for dbAttribute in resourceAttrsList:
            attrName = dbAttribute[0][1]
            # The key here is the following query to get the ID of the J2EE resource property element:
            # AdminConfig.getid('/JDBCProvider:JDBC_Provider_Name/DataSource:DataSource_Name/J2EEResourcePropertySet:/J2EEResourceProperty:URL/')
            attrNameId = getObjectId(dsScope, 'J2EEResourcePropertySet:/J2EEResourceProperty', attrName)
            AdminUtilities.debugNotice("Attribute Name ID: %s" % (attrNameId))
            AdminUtilities.debugNotice("Attribute Values : %s" % (str(dbAttribute+[["required", "true"]])))
            AdminConfig.modify(attrNameId, str(dbAttribute+[["required", "true"]]).replace(',', ''))

        # Get the Mapping module Id associated with the DataSource
        mappingModuleId = AdminConfig.showAttribute(dataSourceId, 'mapping')
        AdminUtilities.debugNotice("Mapping Module ID: %s" % (mappingModuleId))
        if mappingModuleId:
          AdminConfig.modify(mappingModuleId, str(mapModuleData).replace(',', ''))

        # Set the Connection Pool Params - the modify() takes a mangled array of arrays with no commas
        if connectionPoolAttrsList:
          connectionPool = AdminConfig.showAttribute(dataSourceId, 'connectionPool')
          AdminUtilities.debugNotice("Connection Pool ID: %s" % (connectionPool))
          AdminConfig.modify(connectionPool, str(connectionPoolAttrsList).replace(',', ''))

        # Save this JDBC DataSource
        AdminConfig.save()
        return

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

# And now - modify the JDBC Data Source
modifyDataSourceAtScope(scope, provider, ds_name, jndi_name, cmp_enabled, ds_helper, map_alias, container_auth_alias, xa_recovery_auth_alias, component_auth_alias, extra_attrs, resource_attrs, cpool_attrs)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)
    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      err = <<-EOT
      Could not update JDBC Data Source: #{resource[:ds_name]}
      EOT
      raise Puppet::Error, err
    end
    debug "Result:\n#{result}"

    case resource[:scope]
    when %r{(server|node)}
      sync_node
    end
  end
end
