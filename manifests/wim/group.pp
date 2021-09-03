# @summary
#   Defined type to manage a WebSphere group in the default WIM file based realm. 
#
# @example Manage a group with members and roles:
#   websphere_application_server::wim::group { 'my_was_group':
#     ensure          => 'present',
#     description     => 'Puppet Managed Websphere Group',
#     members         => ['jbloggs', 'foo_group', 'bar', 'baz'],
#     enforce_members => true,
#     roles           => ['administrator','operator','configurator'],
#     profile_base    => '/opt/IBM/WebSphere/AppServer/profiles',
#     dmgr_profile    => 'PROFILE_DMGR_01',
#     user            => 'wasadmin',
#     wsadmin_user    => 'admin',
#     wsadmin_pass    => 'password',
#   }
#
# The type manages the creation, updates and deletion of a Websphere group. It controls the group membership and role assignments
# @param ensure
#   Required. Specifies whether this WAS group should exist or not.
# @param description
#   Required. Specifies a group name description for the group ID
# @param members
#   Optional. Specifies a list of members of the group. The members can be users or other groups - but they have to exist prior to addition.
# @param enforce_members
#   Optional. Defines whether the list of members is strictly enforced. If set to true, this means that members which are added outside Puppet control via the WebUI, will be removed next time Puppet runs.
# @param roles
#   Optional. And array of roles to be assigned to the group. The roles are predefined by Websphere and can be any combination of the following: 'administrator','operator','configurator','monitor','deployer','adminsecuritymanager','nobody','iscadmins', 'auditor'. By default, a WAS group is not asigned any roles. If specified, the roles management is strict.
# @param profile_base
#   Required. The full path to the profiles directory where the `dmgr_profile` can  be found. The IBM default is `/opt/IBM/WebSphere/AppServer/profiles`.
# @param cell
#   Required. Specifies the cell where the cluster is, under which this member should be managed.
# @param dmgr_profile
#   Required. The name of the DMGR profile to create this cluster member under.
# @param user
#   Optional. The user to run the `wsadmin` command as. Defaults to 'root'.

define websphere_application_server::wim::group (
  String $description,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Array[String] $members           = undef,
  Boolean $enforce_members         = undef,
  Array[String] $roles             = undef,
  Enum['present','absent'] $ensure = 'present',
  String $user                     = $::websphere_application_server::user,
  String $wsadmin_user             = undef,
  String $wsadmin_pass             = undef,
) {

  websphere_group { $title:
    ensure          => $ensure,
    description     => $description,
    members         => $members,
    enforce_members => $enforce_members,
    roles           => $roles,
    profile_base    => $profile_base,
    dmgr_profile    => $dmgr_profile,
    cell            => $cell,
    user            => $user,
    wsadmin_user    => $wsadmin_user,
    wsadmin_pass    => $wsadmin_pass,
  }
}
