# lint:ignore:140chars
# @summary
#   Defined type to manage a WebSphere Authentication Data Entry (alias) for a J2EE Connector architecture (J2C) connector in the global securityor security domain configuration. 
#       This implementation only manages the global security configuration which is chosen by default when no '-securityDomainName' argument is specified.
#
# @example Manage an authentication data entry (alias):
#   websphere_application_server::sec::jaas::j2c::alias { 'j2c_alias':
#     ensure          => 'present',
#     userid          => 'jbloggs',
#     password        => Sensitive('alias_passw00rd'),
#     manage_password => true,
#     description     => 'J2C auth data entry for jbloggs',
#     profile_base    => '/opt/IBM/WebSphere/AppServer/profiles',
#     dmgr_profile    => 'PROFILE_DMGR_01',
#     cell            => 'CELL_01',
#     user            => 'wasadmin',
#     wsadmin_user    => 'admin',
#     wsadmin_pass    => 'password',
#   }
#
# The type manages the creation, updates and deletion of a Websphere Authentication Data Entry (alias).
# @param ensure
#   Required. Specifies whether this WAS Authentication Data Entry (alias) should exist or not.
# @param userid
#   Required. Specifies the user it should apply to.
# @param description
#   Required. Specifies a free text description to be associated with this alias.
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
define websphere_application_server::sec::jaas::j2c::alias (
  String $userid,
  String $description,
  Variant[String, Sensitive[String]] $password,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Boolean $manage_password         = true,
  Enum['present','absent'] $ensure = 'present',
  String $user                     = $::websphere_application_server::user,
  String $wsadmin_user             = undef,
  String $wsadmin_pass             = undef,
) {

  websphere_authalias { $title:
    ensure          => $ensure,
    userid          => $userid,
    password        => $password,
    manage_password => $manage_password,
    description     => $description,
    profile_base    => $profile_base,
    dmgr_profile    => $dmgr_profile,
    cell            => $cell,
    user            => $user,
    wsadmin_user    => $wsadmin_user,
    wsadmin_pass    => $wsadmin_pass,
  }
}
