# frozen_string_literal: true

require_relative '../websphere_helper'

Puppet::Type.type(:websphere_user).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage WebSphere users in the default WIM file based realm

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-wimmanagementcommands-command-group-admintask-object#rxml_atwimmgt__cmd3

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC
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

  # Create a given user
  def create
    cmd = <<-END.unindent
    # Create user for #{resource[:userid]}
    AdminTask.createUser(['-uid', #{resource[:userid]}, '-password', #{resource[:password]}, '-cn', #{resource[:common_name]}, '-sn', #{resource[:surname]}])
    AdminConfig.save()
    END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:userid], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create user: #{resource[:userid]}
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
  # or "wim:sn" or "wim:email" or "*" for all of them.
  #
  def get_userid_data(field)
    if File.exist?(scope('file'))
      doc = REXML::Document.new(File.open(scope('file')))

      userid = XPath.first(doc, "//wim:Root/wim:entities [@xsi:type='wim:PersonAccount']/wim:uid [text()='#{resource[:userid]}']")
      field_data = XPath.first(userid, "following-siblings::#{field}") if userid

      debug "#{field} for #{resource[:userid]} is: #{field_data}"

      return field_data.to_s if field_data
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

  # Check to see if a user exists.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:userid]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    #path = XPath.first(doc, "//variables:VariableMap/entries[@symbolicName='#{resource[:variable]}']")
    #value = XPath.first(path, '@symbolicName') if path
    userid = XPath.first(doc, "//wim:Root/wim:entities [@xsi:type='wim:PersonAccount']/wim:uid [text()='#{resource[:userid]}']")
    values = Array[XPath.match(doc, "//wim:Root/wim:entities [@xsi:type='wim:PersonAccount']/wim:uid [text()='#{resource[:userid]}']/following-siblings::*")] if userid

    debug "Exists? result for #{resource[:userid]} is: #{userid}"

    !userid.nil?
  end

  # Get a user's given name
  def common_name
    get_userid_data('wim:cn')
  end

  # Set a user's given name
  def common_name=(_val)
    cmd = <<-END.unindent
    # Update value for #{resource[:common_name]}
    uniqueName = AdminTask.searchUsers(['-uid', #{resource[:userid]}])
    if len(uniqueName):
        AdminTask.updateUser(['-uniqueName', uniqueName, '-cn', #{resource[:common_name]}])
    AdminConfig.save()
    END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end

  # Get a user's surname
  def surname
    get_userid_data('wim:sn')
  end

  # Set a user's surname
  def surname=(_val)
    cmd = <<-END.unindent
    # Update description for #{resource[:surname]}
    uniqueName = AdminTask.searchUsers(['-uid', #{resource[:userid]}])
    if len(uniqueName):
        AdminTask.updateUser(['-uniqueName', uniqueName, '-sn', #{resource[:surname]}])
    AdminConfig.save()
    END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end

  # Get a user's mail
  def mail
    get_userid_data('wim:mail')
  end

  # Set a user's mail
  def mail=(_val)
    cmd = <<-END.unindent
    # Update description for #{resource[:mail]}
    uniqueName = AdminTask.searchUsers(['-uid', #{resource[:userid]}])
    if len(uniqueName):
        AdminTask.updateUser(['-uniqueName', uniqueName, '-mail', #{resource[:mail]}])
    AdminConfig.save()
    END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end

  # Checking the passwords from here is probably not desirable: Jython is incredibly slow.
  # If this needs to be done for 50-100 users, the puppet run will take a very long time.
  # 
  # Leave it in for now - for testing purposes.
  def password
    cmd = <<-END.unindent
    # Check the password - we need to find the SecurityAdmin MBean.
    # If there is more than one, we just take the first.
    # This may be a tad slow. (undestatement of the century)
    # If you have tens of users, perhaps this is not a good way
    # to ensure the passwords are reset to what they should be.
    secadms = AdminControl.queryNames("type=SecurityAdmin,*")
    if len(secadms) == 0:
        print "Unable to detect any Security MBeans."
        sys.exit(1)

    secadmbean = secadms.split("\\n")[0]
    plist = "#{resource[:userid]}" + " " + "#{resource[:password]}" + " " + "[]";

    # the following command throws an exception and exits the
    # script if the password doesn't match.
    AdminControl.invoke(secadmbean, "checkPassword", plist)
    END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
    # What would you even return here?
    return password if $? == 0
  end

  # Remove a given user - we try to find it first, and if it does exist
  # we remove the user.
  def destroy
    cmd = <<-END.unindent
    uniqueName = AdminTask.searchUsers(['-uid', #{resource[:userid]}])
    if len(uniqueName):
        AdminTask.deleteUser(['-uniqueName', uniqueName])

    AdminConfig.save()
    END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # We could do the user attributes updates here - so that we save having to run
    # jython half a billion times and take forever in the process.
    # We must be careful about trying to update a deleted user because you can
    # envisage someone setting cn => 'joe' and ensure => 'absent' at the same time.
    # Stupid, but can happen.
  end
end
