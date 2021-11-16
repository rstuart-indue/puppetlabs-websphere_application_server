# lint:ignore:140chars
# @summary
#   Defined type to manage a WebSphere Queue JMS resource. 
#
# @example Manage a Queue resource:
#   websphere_application_server::resources::jms::queue { 'PUPQ':
#     ensure       => 'present',
#     jndi_name    => 'jms/PUPQ',
#     queue_name   => 'PUPPET.TESTQ',
#     description  => 'Puppet Queue',
#     q_data       => $q_data_hash,
#     scope        => 'cluster',
#     cluster      => 'CLUSTER_01',
#     profile_base => '/opt/IBM/WebSphere/AppServer/profiles',
#     dmgr_profile => 'PROFILE_DMGR_01',
#     cell         => 'CELL_01',
#     user         => 'wasadmin',
#     wsadmin_user => 'admin',
#     wsadmin_pass => 'password',
#   }
#
# The type manages the creation, updates and deletion of a Websphere JMS Queue resource.
# @param ensure
#   Required. Specifies whether this WAS Queue resource should exist or not.
# @param jndi_name
#   Optional. Specifies the JNDI Name associated with the Queue. Defaults to `jms/${title}`.
# @param description
#   Required. Specifies a free text description to be associated with this Queue.
# @param q_data
#   Optional. A hash containing the Queue Manager details. The q_data hash keys are underscore-separated versions of the camel-case params in the WAS manual. For example the hash key floating_point_encoding maps to the -floatingPointEncoding param.
# @param custom_properties
#   Optional. A hash containing this Queue's personalized custom_properties settings. This parameter specifies custom properties to be passed to the IBM MQ messaging provider queue type destination implementation. Typically, custom properties are used to set attributes of the queue type destination which are not directly supported through the WebSphere administration interfaces.
# @param scope
#   Required. The scope of this Queue resource. Can be 'cell','cluster','node' or 'server'.
# @param cluster
#   Optional. The cluster name for this Queue resource to be set under. Required if `scope` is set to `cluster`
# @param node_name
#   Optional. The node name for this Queue resource to be set under. Required if `scope` is set to `node`
# @param server
#   Optional. The server name for this Queue resource to be set under. Required if `scope` is set to `server`
# @param cell
#   Required. Specifies the cell where the cluster is, under which this member should be managed. Also used for where this Queue resource will be set under if `scope` is set to `cell`
# @param profile_base
#   Required. The full path to the profiles directory where the `dmgr_profile` can  be found. The IBM default is `/opt/IBM/WebSphere/AppServer/profiles`.
# @param dmgr_profile
#   Required. The name of the DMGR profile to create this cluster member under.
# @param user
#   Optional. The user to run the `wsadmin` command as. Defaults to 'root'.
# @param wsadmin_user
#   Optional. The username for `wsadmin` authentication if security is enabled.
# @param wsadmin_pass
#   Optional. The password for `wsadmin` authentication if security is enabled.
# lint:endignore
define websphere_application_server::resources::jms::queue (
  String $queue_name,
  String $description,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Enum['cell','cluster','node','server'] $scope,
  Enum['present','absent'] $ensure        = 'present',
  String $jndi_name                       = "jms/${title}",
  Variant[Hash, Undef] $q_data            = undef,
  Variant[Hash, Undef] $custom_properties = undef,
  Variant[String, Undef] $cluster         = undef,
  Variant[String, Undef] $node_name       = undef,
  Variant[String, Undef] $server          = undef,
  String $user                            = $::websphere_application_server::user,
  Variant[String, Undef] $wsadmin_user    = undef,
  Variant[String, Undef] $wsadmin_pass    = undef,
) {

  websphere_queue { $title:
    ensure            => $ensure,
    description       => $description,
    jndi_name         => $jndi_name,
    queue_name        => $queue_name,
    q_data            => $q_data,
    custom_properties => $custom_properties,
    scope             => $scope,
    profile_base      => $profile_base,
    dmgr_profile      => $dmgr_profile,
    cell              => $cell,
    cluster           => $cluster,
    node_name         => $node_name,
    server            => $server,
    user              => $user,
    wsadmin_user      => $wsadmin_user,
    wsadmin_pass      => $wsadmin_pass,
  }
}
