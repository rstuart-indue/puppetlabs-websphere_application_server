# lint:ignore:140chars
# @summary
#   Defined type to manage a WebSphere Queue Connection Factory JMS resource. 
#
# @example Manage a QCF resource:
#   websphere_application_server::resources::jms::qcf { 'QCF':
#     ensure       => 'present',
#     description  => 'Puppet Queue Connection Factory',
#     jndi_name    => 'jms/PUPQCF',
#     qmgr_data    => $qmgr_data_hash,
#     conn_pool    => $connection_pool_hash,
#     sess_pool    => $session_pool_hash,
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
# The type manages the creation, updates and deletion of a Websphere JMS Queue Connection Factory (QCF) resource.
# @param ensure
#   Required. Specifies whether this WAS Queue Connection Factory resource should exist or not.
# @param userid
#   Required. Specifies the user it should apply to.
# @param description
#   Required. Specifies a free text description to be associated with this QCF.
# @param password
#   Required. Specifies the alias' password. Note the manage_password boolean parameter.
# @param manage_password
#   Optional. Defaults to `true`. The alias password is checked and maintaned to the value specified in the 'password' parameter
# @param profile_base
#   Required. The full path to the profiles directory where the `dmgr_profile` can  be found. The IBM default is `/opt/IBM/WebSphere/AppServer/profiles`.
# @param cell
#   Required. Specifies the cell where the cluster is, under which this member should be managed.
# @param dmgr_profile
#   Required. The name of the DMGR profile to create this cluster member under.
# @param user
#   Optional. The user to run the `wsadmin` command as. Defaults to 'root'.
# @param wsadmin_user
#   Optional. The username for `wsadmin` authentication if security is enabled.
# @param wsadmin_pass
#   Optional. The password for `wsadmin` authentication if security is enabled.
# lint:endignore
define websphere_application_server::resources::jms::qcf (
  String $description,
  Hash $qmgr_data,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Enum['cell','cluster','node','server'] $scope,
  Enum['present','absent'] $ensure = 'present',
  String $jndi_name                = "jms/${title}",
  Hash $conn_pool                  = undef,
  Hash $sess_pool                  = undef,
  String $cluster                  = undef,
  String $node                     = undef,
  String $server                   = undef,
  String $user                     = $::websphere_application_server::user,
  String $wsadmin_user             = undef,
  String $wsadmin_pass             = undef,
) {

  websphere_cf { $title:
    ensure       => $ensure,
    cf_type      => 'QCF',
    description  => $description,
    jndi_name    => $jndi_name,
    qmgr_data    => $qmgr_data,
    conn_pool    => $conn_pool,
    sess_pool    => $sess_pool,
    scope        => $scope,
    profile_base => $profile_base,
    dmgr_profile => $dmgr_profile,
    cell         => $cell,
    cluster      => $cluster,
    node         => $node,
    server       => $server,
    user         => $user,
    wsadmin_user => $wsadmin_user,
    wsadmin_pass => $wsadmin_pass,
  }
}
