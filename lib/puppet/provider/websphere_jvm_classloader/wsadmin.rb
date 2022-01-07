# frozen_string_literal: true

require 'English'
require_relative '../websphere_helper'

Puppet::Type.type(:websphere_jvm_classloader).provide(:wsadmin, parent: Puppet::Provider::Websphere_Helper) do
  desc <<-DESC
    Provider to manage or create a class loader at a specific scope.

    Please see the IBM documentation available at:
    https://www.ibm.com/docs/en/was-nd/9.0.5?topic=environment-class-loading
    https://www.ibm.com/docs/en/was-nd/9.0.5?topic=loading-class-loaders
    https://www.ibm.com/docs/en/was-nd/9.0.5?topic=loading-class-loader-collection

    It is recommended to consult the IBM documentation as the Class Loader subject is sufficiently
    complex.

    This provider will not allow the creation of a dummy classloader instance (i.e. - no shared libraries)
    This provider will now allow the changing of:
      * the name of the class loader object - the ID is automatically assigned and not changeable.
      * the mode of the class loader object - because the class-loaders are not named it is impossible
                                              to always guess correctly which classloader to change mode for.
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
    @old_classloader_data = {}

    # Dynamic debugging
    @jython_debug_state = Puppet::Util::Log.level == :debug
  end

  # This type only supports a 'server' scope - because server.xml file exists only in that scope.
  def scope(what)
    file = "#{resource[:profile_base]}/#{resource[:dmgr_profile]}"
    case resource[:scope]
    when 'server'
      query = "/Cell:#{resource[:cell]}/Node:#{resource[:node_name]}/Server:#{resource[:server]}"
      mod   = "cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}"
      file += "/config/cells/#{resource[:cell]}/nodes/#{resource[:node_name]}/servers/#{resource[:server]}/server.xml"
    else
      raise Puppet::Error, "Unknown or unsupported scope: #{resource[:scope]}"
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

  # Create a Class Loader
  def create

    # Set the scope for this - we are interested for the ApplicationServer scope inside the named Server.
    appserver_scope = scope('query') + '/ApplicationServer:/' 

    # Convert this to a dumb string (square brackets and all) to pass to Jython
    shared_libs_str = resource[:shared_libs].to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our ClassLoader creation
mode = '#{resource[:mode]}'
appserver_scope = '#{appserver_scope}'
shared_libs = #{shared_libs_str}

msgPrefix = 'WASClassloader create:'

try:
  # Get the AppserverID from the assembled scope
  appserver = AdminConfig.getid(appserver_scope)

  # Create a Classloader inside the AppserverID
  classloader = AdminConfig.create('Classloader', appserver, [['mode', mode]])
  AdminUtilities.debugNotice("Created classloader: " + str(classloader))

  # Cycle through the array of shared libs and create references for every one of them.
  for libref in shared_libs:
    result = AdminConfig.create('LibraryRef', classloader, [['libraryName', libref], ['sharedClassloader', 'true']])
    AdminUtilities.debugNotice("Created shared lib reference: " + str(result))
  #endFor

  AdminConfig.save()
except:
  typ, val, tb = sys.exc_info()
  if (typ==SystemExit):  raise SystemExit,`val`
  if (failonerror != AdminUtilities._TRUE_):
    print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
    val = "%s %s" % (sys.exc_type, sys.exc_value)
    raise Exception("ScriptLibraryException: " + val)
  else:
    AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
  #endIf
#endTry

END

    debug "Running command: #{cmd} as user: #{resource[:user]}"
    result = wsadmin(file: cmd, user: resource[:user], failonfail: false)

    if %r{Invalid parameter value "" for parameter "parent config id" on command "create"}.match?(result)
      ## I'd rather handle this in the Jython, but I'm not sure how.
      ## This usually indicates that the server isn't ready on the DMGR yet -
      ## the DMGR needs to do another Puppet run, probably.
      err = <<-EOT
      Could not create Activation Specs: #{resource[:as_name]} of type #{resource[:destination_type]}
      This appears to be due to the remote resource not being available.
      Ensure that all the necessary services have been created and are running
      on this host and the DMGR. If this is the first run, the cluster member
      may need to be created on the DMGR.
      EOT

      raise Puppet::Error, err

    end

    debug result
  end

  # Check to see if a Class Loader exists - must return a boolean.
  def exists?
    unless File.exist?(scope('file'))
      return false
    end

    debug "Retrieving value of #{resource[:jcl_name]} from #{scope('file')}"
    doc = REXML::Document.new(scope('file'))

    # Remember that classloaders are not named and as such, we can't look for a specific one.
    # The way this bit of code works is to attempt to make an 'educamacated guess' about where to jam
    # any new classloaders.
    # This whole thing is really quite strange, as we have to treat the whole list of classloaders and references to
    # shared libraries as two "mixed bags" - from where we pull just what we're interested in.
    # Let's assume that the type is instructed to ensure the following
    # shared libraries are part of the class loader grab-bags.
    #
    #    shared_libs => ['FOO', 'QUUX', 'BAZ']
    #    mode        => 'PARENT_LAST'
    #
    # This method build a hash of hashes which ultimately will look like this:
    #   {
    #    :PARENT_LAST=>
    #      {
    #         :combined_classloaders=> ["QUUX", "BAR", "QUUX", "FOO"],
    #         :target_classloader=>"Classloader_1639635640366",
    #         :target_score=>1,
    #         :target_add=>["BAZ"],
    #         :target_del=>["BAR"],
    #         :Classloader_1639541168734=>["QUUX"],
    #         :Classloader_1639635640366=>["BAR", "QUUX", "FOO"]
    #      },
    #   :PARENT_FIRST=>
    #      {
    #         :combined_classloaders=>["FOO", "QUUX", "BAZ"],
    #         :target_classloader=>"Classloader_1639727925384",
    #         :target_score=>2,
    #         :target_add=>["BAZ", "QUUX"],
    #         :target_del=>[],
    #         :Classloader_1639727967909=>["QUUX"],
    #         :Classloader_1639727925384=>["FOO"],
    #         :Classloader_1639728014842=>["BAZ"]
    #      }
    #   }
    # If anyone knows a better way to do this, I'm all ears.
    # We're looking for Class Loader entries. We have to ensure we're looking under the correct components entry.
    component_entry = XPath.first(doc,"/process:Server[@clusterName='#{resource[:cluster]}']/components[@xmi:type='applicationserver:ApplicationServer']")

    debug "Discovered component_entry: #{component_entry}"
    
    # Let's say we found a "classloader"
    XPath.each(component_entry, "classloaders[contains(@xmi:id, 'Classloader_')]")  { |cl|
        cl_name, cl_mode = XPath.match(cl, "@*[local-name()='id' or local-name()='mode']")
        cl_mode_s = cl_mode.value.to_sym
        cl_name_s = cl_name.value.to_sym

        debug "Discovered Classloader ID: #{cl_name.value} with mode: #{cl_mode.value}"

        # Extract an array of shared libs configured for this Classloader. We don't care if it contains
        # duplicates, apparently it's quite OK.
        shared_libs = (XPath.match(cl, "libraries/@libraryName")).map{ |shlib| shlib_val = shlib.value }

        debug "Discovered library refs ID: #{shared_libs.to_s}"

        # TODO: This may need to move into the ruby type
        #       Or maybe the Ruby type just uses the score
        #       and computes what it needs to do?
        #
        # Compute what needs to be added/deleted (if anything)
        add_diff = resource[:shared_libs].sort - shared_libs.sort
        del_diff = shared_libs.sort - resource[:shared_libs].sort

        # Initialize these, if this is the first time through the loop
        @old_classloader_data[cl_mode_s] = {} unless @old_classloader_data.key?(cl_mode_s)
        @old_classloader_data[cl_mode_s][:combined_classloaders] = [] unless @old_classloader_data[cl_mode_s].key?(:combined_classloaders)

        # Load sub-hash keyed on the classloader ID and its value set to the array of shared libs.
        # Additionally, make a combined_classloaders array which contains all the shared lib across all the
        # Classloaders of this particular 'mode'
        @old_classloader_data[cl_mode_s][cl_name_s] = shared_libs
        @old_classloader_data[cl_mode_s][:combined_classloaders].push(*shared_libs)

        # While we're here, compute a score for the most appropriate class-loader
        # to modify. The lowest score wins - which means we have to ad the least
        # number of shared libs.
        if ( !@old_classloader_data[cl_mode_s].key?(:target_classloader)) || (add_diff.count < @old_classloader_data[cl_mode_s][:target_score])
            @old_classloader_data[cl_mode_s][:target_classloader] = cl_name.value
            @old_classloader_data[cl_mode_s][:target_score] = add_diff.count
            @old_classloader_data[cl_mode_s][:target_add] = add_diff
            @old_classloader_data[cl_mode_s][:target_del] = del_diff
        end   
    } unless component_entry.nil?

    # This detects whether we are OK *over all* the classloaders in the expected mode
    # By substracting the "detected" classloaders from the "expected" classloaders, we see if we've
    # got a remainder. If the count of the difference is as big as the count of the expected classloaders
    # this means we've got no classloaders configured. Otherwise, we've got *some* of them.
    if @old_classloader_data.key?(resource[:mode])
        combined_diff = resource[:shared_libs].sort - @old_classloader_data[resource[:mode]][:combined_classloaders].sort
    end

    # And now, close the deal, say whether the classloader "conditions" exist or not.
    # Based on this - we decide to either create a classloader, or modify the target one above.
    if (combined_diff.nil? || (combined_diff.count == resource[:shared_libs].count))
        debug "Specified Classloaders for #{resource[:mode]} are all missing: #{resource[:shared_libs].to_s}"
        return false
    else
        debug "Specified Classloaders for #{resource[:mode]} exist - #{combined_diff.count} missing: #{combined_diff.to_s}"
        return true
    end
  end

  # Get the "guessed" classloader mode
  def mode
    @old_classloader_data[:description]
  end

  # Set the mode for guessed classloader
  def mode=(val)
    @property_flush[:description] = val
  end

  # Get the shared libs list for the "guessed classloader
  def shared_libs
    @old_classloader_data[:destinationType]
  end

  # Set the classloader shared libs.
  def shared_libs=(val)
    @property_flush[:destinationType] = val
  end

  # Remove classloader. Well, more to the point,
  # the shared libs which are referenced across class-loaders.
  def destroy

    # TODO: 
    # Ok, so I'm cheating a little - not much, but a little.
    # Set the scope for this. This is so that we don't have to look
    # for it all the time.
    classloader_scope = scope('mod') + "|server.xml#" + classloader_id
    
    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our ClassLoader creation
mode = '#{resource[:mode]}'
classloader_scope = '(#{classloader_scope})'

msgPrefix = 'WASClassloader destroy:'

try:
  # Remove an instance of a Classloader
  result = AdminConfig.remove(classloader_scope)
  AdminUtilities.debugNotice("Removed classloader: " + str(classloader_scope))

  AdminConfig.save()
except:
  typ, val, tb = sys.exc_info()
  if (typ==SystemExit):  raise SystemExit,`val`
  if (failonerror != AdminUtilities._TRUE_):
    print "Exception: %s %s " % (sys.exc_type, sys.exc_value)
    val = "%s %s" % (sys.exc_type, sys.exc_value)
    raise Exception("ScriptLibraryException: " + val)
  else:
    AdminUtilities.fail(msgPrefix+AdminUtilities.getExceptionText(typ, val, tb), failonerror)
  #endIf
#endTry

END

    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug result
  end

  def flush
    # If we haven't got anything to modify, we've got nothing to flush. Otherwise
    # parse the list of things to do
    return if @property_flush.empty?

    # If we don't have to add any shared libs, and we don't enforce strict management, then
    # we don't care about libs to remove, so we bail before we execute the Jython code.
    # However, it will complain every time it runs that the arrays look different and that
    # it would attempt to fix them...
    #return if add_lib_refs.empty? && (resource[:enforce_shared_libs] != :true)

    # Set the scope for this - we are interested for the ApplicationServer scope inside the named Server.
    appserver_scope = scope('query') + '/ApplicationServer:/'

    # TODO: 
    # Ok, so I'm cheating a little - not much, but a little.
    # Set the scope for this.
    classloader_scope = scope('mod') + "|server.xml#" + classloader_id

    # Convert this to a dumb string (square brackets and all) to pass to Jython
    shared_libs_str = resource[:shared_libs].to_s.tr("\"", "'")

    cmd = <<-END.unindent
import AdminUtilities

# Enable debug notices ('true'/'false')
AdminUtilities.setDebugNotices('#{@jython_debug_state}')

# Parameters we need for our ClassLoader creation
mode = '#{resource[:mode]}'
appserver_scope = '#{appserver_scope}'
shared_libs = #{shared_libs_str}

# Get the AppserverID from the assembled scope
#appserver = AdminConfig.getid(appserver_scope)
#
# Create a Classloader inside the AppserverID
#classloader = AdminConfig.create('Classloader', appserver, [['mode', mode]])
#
# Cycle through the array of shared libs and create references for every one of them.
#for libref in shared_libs:
#    result = AdminConfig.create('LibraryRef', classloader, [['libraryName', libref], ['sharedClassloader', 'true']])
#    AdminUtilities.debugNotice("Created shared lib: " + str(result))
##endFor
#
#AdminConfig.save()
END
    debug "Running #{cmd}"
    result = wsadmin(file: cmd, user: resource[:user])
    debug "result: #{result}"
  end
end
