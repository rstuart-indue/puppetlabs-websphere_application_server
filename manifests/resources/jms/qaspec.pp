# lint:ignore:140chars
# @summary
#   Defined type to manage a WebSphere Queue Activation Spec JMS resource. 
#
# @example Manage a QAS resource:
#   websphere_application_server::resources::jms::qaspec { 'PUPQASPEC':
#     ensure           => 'present',
#     jndi_name        => 'eis/PUPQASPEC',
#     destination_jndi => 'jms/PUPQ',
#     description      => 'Puppet Queue Activation Spec',
#     qmgr_data        => $qmgr_data_hash,
#     scope            => 'cluster',
#     cluster          => 'CLUSTER_01',
#     profile_base     => '/opt/IBM/WebSphere/AppServer/profiles',
#     dmgr_profile     => 'PROFILE_DMGR_01',
#     cell             => 'CELL_01',
#     user             => 'wasadmin',
#     wsadmin_user     => 'admin',
#     wsadmin_pass     => 'password',
#   }
#
# The type manages the creation, updates and deletion of a Websphere JMS Queue Activation Spec(Q ASpec) resource.
# @param ensure
#   Required. Specifies whether this WAS Queue Activation Spec resource should exist or not.
# @param jndi_name
#   Optional. Specifies the JNDI Name for this Q ASpec. Defaults to `eis/${title}`.
# @param destination_jndi
#   Required. Specifies the Destination JNDI Name this Q ASpec points at.
# @param description
#   Required. Specifies a free text description to be associated with this Q ASpec.
# @param qmgr_data
#   Required. A hash containing the Queue Manager details. At the very least it should contain information about the target MQ servers and connection settings.
# @param scope
#   Required. The scope of this Q ASpec resource. Can be 'cell','cluster','node' or 'server'.
# @param cluster
#   Optional. The cluster name for this Q ASpec resource to be set under. Required if `scope` is set to `cluster`
# @param node_name
#   Optional. The node name for this Q ASpec resource to be set under. Required if `scope` is set to `node`
# @param server
#   Optional. The server name for this Q ASpec resource to be set under. Required if `scope` is set to `server`
# @param cell
#   Required. Specifies the cell where the cluster is, under which this member should be managed. Also used for where this Q ASpec resource will be set under if `scope` is set to `cell`
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
define websphere_application_server::resources::jms::qaspec (
  String $description,
  Hash $qmgr_data,
  String $destination_jndi,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Enum['cell','cluster','node','server'] $scope,
  Enum['present','absent'] $ensure     = 'present',
  String $jndi_name                    = "eis/${title}",
  Variant[String, Undef] $cluster      = undef,
  Variant[String, Undef] $node_name    = undef,
  Variant[String, Undef] $server       = undef,
  String $user                         = $::websphere_application_server::user,
  Variant[String, Undef] $wsadmin_user = undef,
  Variant[String, Undef] $wsadmin_pass = undef,
) {

  websphere_activationspec { $title:
    ensure           => $ensure,
    description      => $description,
    jndi_name        => $jndi_name,
    destination_type => 'javax.jms.Queue',
    destination_jndi => $destination_jndi,
    qmgr_data        => $qmgr_data,
    scope            => $scope,
    profile_base     => $profile_base,
    dmgr_profile     => $dmgr_profile,
    cell             => $cell,
    cluster          => $cluster,
    node_name        => $node_name,
    server           => $server,
    user             => $user,
    wsadmin_user     => $wsadmin_user,
    wsadmin_pass     => $wsadmin_pass,
  }
}
