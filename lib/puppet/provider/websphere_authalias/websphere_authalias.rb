# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_authalias).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage WebSphere authentication data entries for a
    J2EE Connector architecture (J2C) connector in the global security
    or security domain configuration.

    This implementation only manages the global security configuration
    which is chosen by default when no '-securityDomainName' argument
    is specified.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-securityconfigurationcommands-command-group-admintask-object#rxml_7securityconfig__SecurityConfigurationCommands.cmd35

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the user changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize(val = {})
    super(val)
    @property_flush = {}
    @authalias={}
  end

  def scope(what)
    # (cells/CELL_01/nodes/appNode01/servers/AppServer01
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    query = "/Cell:#{resource[:cell]}"
    mod   = "cells/#{resource[:cell]}"
    file += "/config/cells/#{resource[:cell]}/security.xml"

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

  # Create a given J2C authentication data entry
  def create
    cmd = <<-END.unindent
    # Create J2C authentication data entry for #{resource[:aliasid]}
    AdminTask.createAuthDataEntry(['-alias', '#{resource[:aliasid]}', '-password', '#{resource[:password]}', '-user', '#{resource[:userid]}', '-description', '#{resource[:description]}'])
    AdminConfig.save()
    END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create J2C authentication data entry: #{resource[:aliasid]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if an alias exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      debug "Bailing out because security.xml file does not exist..."
      return false
    end

    debug "Retrieving value of #{resource[:aliasid]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))
    j2c_alias = XPath.first(doc, "/security:Security[@xmi:version='2.0']/authDataEntries[@alias='#{resource[:aliasid]}']")
    debug "Found auth data entry for #{resource[:aliasid]} with values: #{j2c_alias}"
    unless j2c_alias.nil?
      aliasid, userid, password, description = Xpath.match(j2c_alias, "@*[local-name()='alias' or local-name()='userId' or local-name()='password' or local-name()='description']")

      @authalias = {
        :aliasid => aliasid,
        :userid => userid,
        :password => password,
        :description => description,
      }

      debug "Found auth data entry for #{resource[:aliasid]} with values: #{authalias}"
    end
    !@authalias.empty?

  end

  # Get the userid associated with the alias
  def userid
    @authalias[:userid]
  end

  # Set the user id 
  def userid=(val)
    @property_flush[:userid] = val
  end

  # Checking/enforcing the passwords from here is probably not desirable: Jython is
  # incredibly slow. If this needs to be done for 50-100 users, the puppet run will
  # take a *very* long time.
  def password
    # Pretend it's all OK if we're not managing the password
    return resource[:password] unless resource[:manage_password] == :true
    return resource[:password]
  end

  def password=(val)
    @property_flush[:password] = val
  end
 
  # Get a description for a given alias
  def description
    @authalias[:description]
  end

  # Set a description for a given alias
  def description=(val)
    @property_flush[:description] = val
  end

  # Remove a given alias
  def destroy
    cmd = <<-END.unindent
    AdminTask.deleteAuthDataEntry(['-alias', '#{resource[:aliasid]}'])

    AdminConfig.save()
    END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
    @authalias.clear
  end

  def flush
    wascmd_args = []

    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return unless @property_flush
    wascmd_args.push("'-user'", "'#{resource[:userid]}'") if @property_flush[:userid]
    wascmd_args.push("'-password'", "'#{resource[:password]}'") if @property_flush[:password]
    wascmd_args.push("'-description'", "'#{resource[:description]}'") if @property_flush[:description]

    # If property_flush had something inside, but wasn't what we expected, we really
    # need to bail, because the list of was command arguments will be empty.
    return if wascmd_args.empty?

    # If we do have to run something, prepend the alias arguments and make a comma
    # separated string out of the whole array.
    arg_string = wascmd_args.unshift("'-alias'", "'#{resources[:aliasid]}'").join(', ')

    cmd = <<-END.unindent
        # Update J2C authentication data entry values for #{resource[:aliasid]}
        aliasDetails = AdminTask.getAuthDataEntry(['-alias', '#{resource[:userid]}'])
        if len(aliasDetails):
            AdminTask.modifyAuthDataEntry([#{arg_string}])
        AdminConfig.save()
        END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: true)
    debug "result: #{result}"
  end
end
