# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_user).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage WebSphere users in the default WIM file based realm

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was/9.0.5?topic=scripting-wimmanagementcommands-command-group-admintask-object#rxml_atwimmgt__cmd3

    We execute the 'wsadmin' tool to query and make changes, which interprets
    Jython. This means we need to use heredocs to satisfy whitespace sensitivity.
    DESC

  # We are going to use the flush() method to enact all the user changes we may perform.
  # This will speed up the application of changes, because instead of changing every
  # attribute individually, we coalesce the changes in one script and execute it once.
  def initialize (_val={})
    super(_val)
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

  # Create a given user
  def create
    cmd = <<-END.unindent
    # Create user for #{resource[:userid]}
    AdminTask.createUser(['-uid', '#{resource[:userid]}', '-password', '#{resource[:password]}', '-cn', '#{resource[:common_name]}', '-sn', '#{resource[:surname]}'])
    AdminConfig.save()
    END

    debug "Running command: #{cmd} as user: resource[:user]"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

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
  # or "wim:sn" or "wim:email" or any other of them.
  #
  def get_userid_data(field)
    if File.exist?(scope('file'))
      doc = REXML::Document.new(File.open(scope('file')))

      field_data = XPath.first(doc, "//[wim:uid='#{resource[:userid]}']/#{field}")

      debug "Getting #{field} for #{resource[:userid]} elicits: #{field_data}"

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

  # Check to see if a user exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:userid]} from #{scope('file')}"
    doc = REXML::Document.new(File.open(scope('file')))

    # We're looking for user-id entries matching our user name
    userid = XPath.first(doc, "//[wim:uid='#{resource[:userid]}']/wim:uid")

    debug "Exists? method result for #{resource[:userid]} is: #{userid}"

    !userid.nil?
  end

  # Get a user's given name
  def common_name
    get_userid_data('wim:cn')
  end

  # Set a user's given name
  def common_name=(_val)
    @property_flush[:common_name] = _val
  end

  # Get a user's surname
  def surname
    get_userid_data('wim:sn')
  end

  # Set a user's surname
  def surname=(_val)
    @property_flush[:surname] = _val
  end

  # Get a user's mail
  def mail
    get_userid_data('wim:mail')
  end

  # Set a user's mail
  def mail=(_val)
    @property_flush[:mail] = _val
  end

  # Checking/enforcing the passwords from here is probably not desirable: Jython is
  # incredibly slow. If this needs to be done for 50-100 users, the puppet run will
  # take a *very* long time.
  #
  # Long story short: we don't know what encryption is used for the WAS user passwords
  # which means that the only way to check them is via this little script - which
  # returns a different non-zero value whether the user doesn't exist, or the password
  # does not match. The drawback is that it takes 8-10 seconds to run. Expand this to
  # more than a handful of users (2-3) and you have a problem.
  # 
  # Also it is likely you want to allow the users to change their own passwords if they
  # are alive users, not machine/service accounts.
  #
  # The work around this is to conditionally check the password based on the newparam
  # resource[:manage_password] - and make that default to false, which will allow to
  # set the password at the account-creation time, but will not care about it afterwards.
  #
  # If clients want force a change for selected accounts, then set the attribute
  # 'manage_password => true' for said accounts.
  def password

    # Pretend it's all OK if we're not managing the password
    return resource[:password] if !resource[:manage_password]

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

    return resource[:password] if $CHILD_STATUS == 0
  end

  def password=(_val)
    @property_flush[:password] = _val
  end

  # Remove a given user - we try to find it first, and if it does exist
  # we remove the user.
  def destroy
    cmd = <<-END.unindent
    uniqueName = AdminTask.searchUsers(['-uid', '#{resource[:userid]}'])
    if len(uniqueName):
        AdminTask.deleteUser(['-uniqueName', uniqueName])

    AdminConfig.save()
    END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    wascmd_args = []
    if @property_flush
      wascmd_args.push("'-cn'", "'#{resource[:common_name]}'") if @property_flush[:common_name]
      wascmd_args.push("'-sn'", "'#{resource[:surname]}'") if @property_flush[:surname]
      wascmd_args.push("'-mail'", "'#{resource[:mail]}'") if @property_flush[:mail]
      wascmd_args.push("'-password'", "'#{resource[:password]}'") if @property_flush[:password]
      unless args.empty?
        # If we do have to run something, prepend the uniqueName arguments and make a comma
        # separated string out of the whole array.
        arg_string = wascmd_args.prepend("'-uniqueName'", 'uniqueName').join(', ')

        cmd = <<-END.unindent
        # Update value for #{resource[:common_name]}
        uniqueName = AdminTask.searchUsers(['-uid', '#{resource[:userid]}'])
        if len(uniqueName):
            AdminTask.updateUser([#{arg_string}])
        AdminConfig.save()
        END
        debug "Running #{cmd}"
        result = wsadmin(file: cmd, user: resource[:user])
        debug "result: #{result}"
      end 
    end
  end
end
