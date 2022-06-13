# frozen_string_literal: true

require 'csv'
require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_jaaslogin).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a JAAS Login at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-configuring-jaas-login-modules-using-wsadmin

    It is recommended to consult the IBM documentation for further clarifications.

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

    # Three ways of defining scope in WAS.
    case target_scope
    when 'cell'
      query = "/Cell:#{resource[:cell]}"
      mod   = "cells/#{resource[:cell]}"
      xml   = "(cell):#{resource[:cell]}"
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

  # Helper method to assemble the login module list and the auth strategies
  # in the order specified by the ordinal number.
  def get_login_modules_strings
    login_module_list = []
    login_module_strategies = []

    resource[:login_modules].each_key { |login_module|
      ordinal = resource[:login_modules][login_module][:ordinal]
      strategy = resource[:login_modules][login_module][:authentication_strategy]

      login_module_list[ordinal] = login_module.to_s
      login_module_strategies[ordinal] = strategy.to_s
    } unless resource[:login_modules].nil?
  
  
    # Return an anonymous hash
    {
      :names_str => login_module_list.compact.to_csv(row_sep: nil),
      :strategies_str => login_module_strategies.compact.to_csv(row_sep: nil),  
    }  
  end

  # Create a JAAS Login Resource
  def create

    # Make a Jython hash out of the custom props if we have any - otherwise pass an empty hash.
    custom_props = {}
    custom_props = resource[:login_modules].select{|module_name,values_hash| values_hash.key?(:custom_properties)} unless resource[:login_modules].nil?
    custom_props_str = custom_props.map { |k, v| [k, "#{v[:custom_properties].map{ |cpk, cpv| "#{cpk}=#{cpv}"}}"]}.to_h.to_json
   
    login_modules_stringified = get_login_modules_strings

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our JAAS Login
jaas_login = '#{resource[:jaas_login]}'
login_type = '#{resource[:login_type]}'
login_modules = '#{login_modules_stringified[:names_str]}'
auth_strategies = '#{login_modules_stringified[:strategies_str]}'
custom_props = #{custom_props_str}

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def createJAASLogin(name, loginType, loginModulesString, authStrategyString, customProperties={},  failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "createJAASLogin(" + `name` +  ", " + `loginType`+ `loginModulesString` + `authStrategyString` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Create a JAAS Login
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminTask: createJAASLogin ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     login type                  "+loginType)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" JAAS Login Modules:")
    AdminUtilities.debugNotice ("     login modules:              "+str(loginModulesString))
    AdminUtilities.debugNotice ("     auth strategies:            "+str(authStrategyString))
    AdminUtilities.debugNotice ("     custom props:               "+str(customProperties))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(loginType) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["loginType", loginType]))

    # Prepare the parameters for the AdminTask command:
    requiredParameters = ["-loginEntryAlias", name, "-loginType", loginType]

    if (loginModulesString != '' and authStrategyString != ''):
      finalAttrsList = requiredParameters + ["-loginModules", loginModulesString, '-authStrategies', authStrategyString]
    else:
      finalAttrsList = requiredParameters
    #endIf

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with loginType: " + str(loginType))
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalAttrsList))

    # Create the JAAS Login Alias
    AdminTask.configureJAASLoginEntry(finalAttrsList)

    # Set the custom properties for all the modules which require them
    if (len(customProperties) != 0):
      for (moduleName,moduleCustomProps) in customProperties.items():
        moduleParams = ['-loginModule', moduleName, '-customProperties', moduleCustomProps]
        AdminUtilities.debugNotice("Setting custom params for login module: %s to %s: " % (moduleName, moduleCustomProps))
        AdminTask.configureLoginModule(requiredParameters + moduleParams)
      #endFor
    #endIf

    # Save this JAAS Login
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

# And now - create the JAAS Login for the given login_type.
createJAASLogin(jaas_login, login_type, login_modules, auth_strategies, custom_props)

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create JAAS Login alias: #{resource[:jaas_login]} for location #{resource[:cell]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a JAAS Login exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:jaas_login]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    sec_entry = XPath.first(doc, "/security:Security")
    login_entry = XPath.first(sec_entry, "#{resource[:login_type]}LoginConfig/entries[@alias='#{resource[:jaas_login]}']/") unless sec_entry.nil?
    debug "Found JAAS Login entry for '#{resource[:jaas_login]}'." unless login_entry.nil?

    ordinal = 0
    XPath.each(login_entry, "loginModules") { |module_entry|
      module_class, auth_strategy = XPath.match(module_entry, "@*[local-name()='moduleClassName' or local-name()='authenticationStrategy']")

      module_class_name = module_class.value.to_sym
      auth_strategy_val = auth_strategy.value.to_s

      debug "Found login module #{module_class_name} with authentication strategy #{auth_strategy_val} in position #{ordinal}."

      @old_conf_details[module_class_name] = {
        :authentication_strategy => auth_strategy_val,
        :ordinal => ordinal,
      }

      # Extract the custom properties from a login module
      custom_properties = {}
      XPath.each(module_entry, "options") { |custom_property|
        prop_name, prop_value = XPath.match(custom_property, "@*[local-name()='name' or local-name()='value']")
        custom_properties[prop_name.value.to_sym]=prop_value.value.to_s
      } unless module_entry.nil?

      # Add the custom properties for this login module, regardless of whether we have discovered any. 
      # We'll clean them later in the login_modules() method
      @old_conf_details[module_class_name].store(:custom_properties, custom_properties)

      # Increment the ordinal number
      ordinal += 1

    } unless login_entry.nil?

    debug "JAAS Login data for #{resource[:jaas_login]} is: #{@old_conf_details}" unless login_entry.nil?
    !login_entry.nil?
  end

  def login_modules
    sanitised_list = @old_conf_details
    resource[:login_modules].keys.each { |login_module|
      if sanitised_list.key?(login_module)
        # Ignore custom_properties if we don't have them in the "SHOULD" hash.
        # Delete them from the returnable hash just so Puppet is 'happy' and move
        # to the next login module
        debug "checking custom_properties for #{login_module}"
        sanitised_list[login_module].delete(:custom_properties) unless resource[:login_modules][login_module].key?(:custom_properties)
      end
    }
    return sanitised_list
  end

  def login_modules=(val)
    @property_flush[:login_modules] = val
  end

  # Remove a given JAAS Login
  def destroy

    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our VHost removal
login_type = '#{resource[:login_type]}'
jaas_login = '#{resource[:jaas_login]}' 

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def deleteJAASLogin(name, loginType, failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "deleteJAASLogin(" + `name` + ", " + `loginType` + ", " + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Delete a JAAS Login
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminTask: deleteJAASLogin ")
    AdminUtilities.debugNotice (" Scope:")
    AdminUtilities.debugNotice ("     loginType:                  "+loginType)
    AdminUtilities.debugNotice (" JAAS Login Name:")
    AdminUtilities.debugNotice ("     alias   :                   "+name)
    AdminUtilities.debugNotice (" Return: NIL")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(loginType) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["loginType", loginType]))

    # Call the corresponding AdminTask command
    AdminUtilities.debugNotice("About to call AdminTask command with loginType: " + str(loginType))
    AdminUtilities.debugNotice("About to call AdminTask command for target JAAS Login alias: " + str(name))

    # Delete the JAAS Login
    AdminTask.unconfigureJAASLoginEntry(['-loginEntryAlias', name, '-loginType', loginType])

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

# And now - delete the JAASLogin
deleteJAASLogin(jaas_login, login_type)

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    # Make a Jython hash out of the custom props if we have any - otherwise pass an empty hash.
    custom_props = {}
    custom_props = resource[:login_modules].select{|module_name,values_hash| values_hash.key?(:custom_properties)} unless resource[:login_modules].nil?
    #custom_props_str = custom_props.map { |k, v| [k, "'#{v[:custom_properties].map{ |cpk, cpv| "#{cpk}=#{cpv}"}}'"]}.to_h.to_json
    debug "CustomProps SHOULD: #{custom_props}"

    # This is a bit of a mind-bender:
    # We calculate the differences between the custom properties in WAS and the ones passed to Puppet
    # What is missing in Puppet means it needs to be deleted from WAS: so we add these "keys" with an empty value
    # because this way WAS will delete them from the config.
    custom_props_str = custom_props.map{|k, v|
      diff_props = @old_conf_details[k][:custom_properties].keys - v[:custom_properties].keys
      diff_props.each {|e| v[:custom_properties].store(e, '')}
      [k, "#{v[:custom_properties].map{ |cpk, cpv| "#{cpk}=#{cpv}"}}"]
    }.to_h.to_json
  
    # Get the list of modules which we need to remove.
    removable_modules = []
    removable_modules = @old_conf_details.keys - resource[:login_modules].keys unless resource[:login_modules].nil?
    removable_modules_str = removable_modules.map{ |e| e.to_s}.to_s

    login_modules_stringified = get_login_modules_strings
    cmd = <<-END.unindent
import AdminUtilities

# Parameters we need for our JAAS Login
jaas_login = '#{resource[:jaas_login]}'
login_type = '#{resource[:login_type]}'
login_modules = '#{login_modules_stringified[:names_str]}'
auth_strategies = '#{login_modules_stringified[:strategies_str]}'
custom_props = #{custom_props_str}
removable_modules = #{removable_modules_str}

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Global variable within this script
bundleName = "com.ibm.ws.scripting.resources.scriptLibraryMessage"
resourceBundle = AdminUtilities.getResourceBundle(bundleName)

def modifyJAASLogin(name, loginType, loginModulesString, authStrategyString, customProperties={}, removeList=[], failonerror=AdminUtilities._BLANK_ ):
  if (failonerror==AdminUtilities._BLANK_):
      failonerror=AdminUtilities._FAIL_ON_ERROR_
  #endIf
  msgPrefix = "modifyJAASLogin(" + `name` +  ", " + `loginType`+ `loginModulesString` + `authStrategyString` + `failonerror`+"): "

  try:
    #--------------------------------------------------------------------
    # Modify a JAAS Login
    #--------------------------------------------------------------------
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" AdminTask: modifyJAASLogin ")
    AdminUtilities.debugNotice (" Target:")
    AdminUtilities.debugNotice ("     login type                  "+loginType)
    AdminUtilities.debugNotice ("     alias                       "+name)
    AdminUtilities.debugNotice (" JAAS Login Modules:")
    AdminUtilities.debugNotice ("     login modules:              "+str(loginModulesString))
    AdminUtilities.debugNotice ("     auth strategies:            "+str(authStrategyString))
    AdminUtilities.debugNotice ("     removable modules:          "+str(removeList))
    AdminUtilities.debugNotice ("     custom props:               "+str(customProperties))
    AdminUtilities.debugNotice (" Return: No return value")
    AdminUtilities.debugNotice ("---------------------------------------------------------------")
    AdminUtilities.debugNotice (" ")

    # Make sure required parameters are non-empty
    if (len(name) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["name", name]))
    if (len(loginType) == 0):
      raise AttributeError(AdminUtilities._formatNLS(resourceBundle, "WASL6041E", ["loginType", loginType]))

    # Prepare the parameters for the AdminTask command:
    requiredParameters = ["-loginEntryAlias", name, "-loginType", loginType]

    if (loginModulesString != '' and authStrategyString != ''):
      finalAttrsList = requiredParameters + ["-loginModules", loginModulesString, '-authStrategies', authStrategyString]
    else:
      finalAttrsList = requiredParameters
    #endIf

    AdminUtilities.debugNotice("About to call AdminTask command with loginType: " + str(loginType))

    # If we have a list of modules to delete - iterate through it and delete them one by one.
    if (len(removeList) !=0 ):
      for targetModule in removeList:
        AdminUtilities.debugNotice("Removing target module %s from login entry: %s" % (targetModule, name))
        AdminTask.unconfigureLoginModule(requiredParameters + ['-loginModule', targetModule])

    # Call the corresponding AdminTask command 
    AdminUtilities.debugNotice("About to call AdminTask command with parameters: " + str(finalAttrsList))

    # Configure the JAAS Login Alias - this will add any extra login modules and
    # set the correct order too.
    AdminTask.configureJAASLoginEntry(finalAttrsList)

    # Set the custom properties for all the modules which require them
    if (len(customProperties) != 0):
      for (moduleName,moduleCustomProps) in customProperties.items():
        moduleParams = ['-loginModule', moduleName, '-customProperties', moduleCustomProps]
        AdminUtilities.debugNotice("Setting custom params for login module: %s to %s: " % (moduleName, moduleCustomProps))
        AdminTask.configureLoginModule(requiredParameters + moduleParams)
      #endFor
    #endIf

    # Save this JAAS Login
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

# And now - modify the JAAS Login.
modifyJAASLogin(jaas_login, login_type, login_modules, auth_strategies, custom_props, removable_modules)    
END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end