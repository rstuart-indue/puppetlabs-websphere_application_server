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

      xpath_group_id = XPath.first(doc, "//wim:entities[@xsi:type='wim:Group']/wim:cn[text()='#{resource[:groupid]}']")
      field_data = XPath.first(xpath_group_id, "following-sibling::#{field}") if xpath_group_id

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

  # Get a group's list of members - users or groups
  def members
    if File.exist?(scope('file'))
      doc = REXML::Document.new(File.open(scope('file')))

      xpath_group_id = XPath.first(doc, "//wim:entities[@xsi:type='wim:Group']/wim:cn[text()='#{resource[:groupid]}']")
      members_data = XPath.match(xpath_group_id, 'following-sibling::wim:members') if xpath_group_id

      debug "Getting wim:members for #{resource[:groupid]} elicits: #{members_data}"

      member_list = []
      XPath.each(xpath_group_id, 'following-sibling::wim:members') do |member|
        # The unique_name is something along the lines of:
        # uid=userName,o=defaultWIMFileBasedRealm -> for a user (note the uid=)
        # cn=groupName,o=defaultWIMFileBasedRealm -> for a group (note the cn=)
        unique_name = XPath.first(member, 'wim:identifier/@uniqueName').to_s

        # Extract the member name: any uid or cn value.
        member_name = unique_name.scan(%r{^(?:uid|cn)=(\w+),o=*})
        member_list.push(member_name) unless member_name.nil?
      end
      debug "Detected member array for group #{resource[:groupid]} is: #{member_list}"

      # rubocop:disable Style/RedundantReturn
      return member_list
      # rubocop:enable Style/RedundantReturn
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

  # Set a group's description name
  def members=(val)
    @property_flush[:members] = val
  end

  # Remove a given group - we try to find it first, and if it does exist
  # we remove the group.
  def destroy
    cmd = <<-END.unindent
    uniqueName = AdminTask.searchGroups(['-cn', '#{resource[:groupid]}'])
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
    member_args = []

    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return unless @property_flush
    wascmd_args.push("'-description'", "'#{resource[:description]}'") if @property_flush[:description]
    member_args = resource[:members] if @property_flush[:members]

    # If property_flush had something inside, but wasn't what we expected, we really
    # need to bail, because the list of was command arguments will be empty. Ditto for
    # member_args.
    return if wascmd_args.empty? && member_args.empty?

    # If we do have to run something, prepend the grpUniqueName arguments and make a comma
    # separated string out of the whole array.
    arg_string = wascmd_args.unshift("'-groupUniqueName'", 'groupUniqueName').join(', ') unless wascmd_args.empty?
    member_string = member_args.map { |e| "'#{e}'" }.join(',') unless member_args.empty?

    cmd = <<-END.unindent
      # Change the Group configuration and/or the group membership for #{resource[:groupid]}
      # When adding group members, this module allows adding other groups, not just users.

      arg_string = [#{arg_string}]
      member_list = [#{member_string}]

      # Get the groupUniqueName for the target group
      groupUniqueName = AdminTask.searchGroups(['-cn', '#{resource[:groupid]}'])

      if len(groupUniqueName):

        # Update group configuration for #{resource[:groupid]}
        if len(arg_string):
          AdminTask.updateGroup(arg_string)

        # Update the group membership for #{resource[:groupid]}
        if len(member_list):
          for member_uid in member_list:
            memberUniqueName=AdminTask.searchUsers(['-uid', member_uid])

            # If we can't find a user, maybe it is a group we need to add, look for it
            if len(memberUniqueName) == 0:
              memberUniqueName=AdminTask.searchGroups(['-cn', member_uid])

            if len(memberUniqueName):
              AdminTask.addMemberToGroup(['-memberUniqueName', memberUniqueName, '-groupUniqueName', groupUniqueName])

        AdminConfig.save()
        END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
