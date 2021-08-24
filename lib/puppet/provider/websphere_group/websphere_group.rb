# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_group).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage WebSphere groups in the default WIM file based realm

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-wimmanagementcommands-command-group-admintask-object#rxml_atwimmgt__cmd3

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the group changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize(val = {})
    super(val)
    @property_flush = {}
  end

  def scope(what)
    # (cells/CELL_01/nodes/appNode01/servers/AppServer01
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    query = "/Cell:#{resource[:cell]}"
    mod   = "cells/#{resource[:cell]}"
    file += "/config/cells/#{resource[:cell]}/fileRegistry.xml"

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

  # Create a given group
  def create
    cmd = <<-END.unindent
    # Create group for #{resource[:groupid]}
    AdminTask.createGroup(['-cn', '#{resource[:groupid]}', '-description', '#{resource[:description]}'])
    AdminConfig.save()
    END

    debug "Running command: #{cmd} as user: resource[:user]"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create group: #{resource[:groupid]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Small helper method so we don't repeat ourselves for the fields
  # we have to keep track on and see if they changed. This method is
  # passed a String argument which is the name of the field/sibling
  # we are trying to get the value for. i.e. it can be "wim:cn"
  # or "wim:description" or any other of them.
  #
  def get_groupid_data(field)
    if File.exist?(scope('file'))
      doc = REXML::Document.new(File.open(scope('file')))

      field_data = XPath.first(doc, "//wim:entities[@xsi:type='wim:Group']/wim:cn[text()='#{resource[:groupid]}']following-sibling::#{field}")

      debug "Getting #{field} for #{resource[:groupid]} elicits: #{field_data}"

      return field_data.text if field_data
    else
      msg = <<-END
      #{scope('file')} does not exist. This may indicate that the cluster
      member has not yet been realized on the DMGR server. Ensure that the
      DMGR has created the cluster member (run Puppet on it?) and that the
      names are correct (e.g. node name, profile name)
      END
      raise Puppet::Error, msg
    end
  end

  # Check to see if a group exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:groupid]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    # We're looking for group-id entries matching our group name
    groupid = XPath.first(doc, "//wim:entities[@xsi:type='wim:Group']/wim:cn[text()='#{resource[:groupid]}']")

    debug "Exists? method result for #{resource[:groupid]} is: #{groupid}"

    !groupid.nil?
  end

  # Get a group's description
  def description
    get_groupid_data('wim:description')
  end

  # Set a group's description name
  def description=(val)
    @property_flush[:description] = val
  end

  # Remove a given group - we try to find it first, and if it does exist
  # we remove the group.
  def destroy
    cmd = <<-END.unindent
    uniqueName = AdminTask.searchGroups(['-uid', '#{resource[:groupid]}'])
    if len(uniqueName):
        AdminTask.deleteGroup(['-uniqueName', uniqueName])

    AdminConfig.save()
    END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    wascmd_args = []

    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return unless @property_flush
    wascmd_args.push("'-description'", "'#{resource[:description]}'") if @property_flush[:description]

    # If property_flush had something inside, but wasn't what we expected, we really
    # need to bail, because the list of was command arguments will be empty.
    return if wascmd_args.empty?

    # If we do have to run something, prepend the uniqueName arguments and make a comma
    # separated string out of the whole array.
    arg_string = wascmd_args.unshift("'-uniqueName'", 'uniqueName').join(', ')

    cmd = <<-END.unindent
        # Update value for #{resource[:common_name]}
        uniqueName = AdminTask.searchGroups(['-uid', '#{resource[:groupid]}'])
        if len(uniqueName):
            AdminTask.updateGroup([#{arg_string}])
        AdminConfig.save()
        END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
