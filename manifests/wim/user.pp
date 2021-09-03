# lint:ignore:140chars
# @summary
#   Defined type to manage a WebSphere user in the default WIM (Websphere Identity Management[?]) file based realm. 
#
# @example Manage a user with members and roles:
#   websphere_application_server::wim::user { 'jbloggs':
#     ensure          => 'present',
#     common_name     => 'Joe',
#     surname         => 'Bloggs',
#     mail            => 'jbloggs@foo.bar.baz.com',
#     password        => Sensitive('some_secret_p@ssw0rd'),
#     manage_password => false,
#     profile_base    => '/opt/IBM/WebSphere/AppServer/profiles',
#     dmgr_profile    => 'PROFILE_DMGR_01',
#     cell            => 'CELL_01',
#     user            => 'wasadmin',
#     wsadmin_user    => 'admin',
#     wsadmin_pass    => 'password',
#   }
#
# The type manages the creation, updates and deletion of a Websphere user. It controls the user details and optionally the user password.
# @param ensure
#   Required. Specifies whether this WAS user should exist or not.
# @param common_name
#   Required. Specifies the user's common name.
# @param surname
#   Required. Specifies the user's surname.
# @param mail
#   Required. Specifies the user's mail.
# @param password
#   Required. Specifies the user's password. Note the manage_password boolean parameter.
# @param manage_password
#   Optional. Defaults to `false`. The verification of a user's password is done via executing a Jython script. This is a very expensive operation which adds approximately 10 seconds for every checked password. More over, it does not permit the users to keep their changed passwords and will cause them to revert to the previous puppet known value. If you need to programatically change the password for a specific user, set `manage_password` to `true`, run puppet, then turn it to `false` again.
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
define websphere_application_server::wim::user (
  String $common_name,
  String $surname,
  String $mail,
  String $password,
  Stdlib::Absolutepath $profile_base,
  String $dmgr_profile,
  String $cell,
  Boolean $manage_password         = false,
  Enum['present','absent'] $ensure = 'present',
  String $user                     = $::websphere_application_server::user,
  String $wsadmin_user             = undef,
  String $wsadmin_pass             = undef,
) {

  websphere_user { $title:
    ensure          => $ensure,
    common_name     => $common_name,
    surname         => $surname,
    mail            => $mail,
    password        => $password,
    manage_password => $manage_password,
    profile_base    => $profile_base,
    dmgr_profile    => $dmgr_profile,
    cell            => $cell,
    user            => $user,
    wsadmin_user    => $wsadmin_user,
    wsadmin_pass    => $wsadmin_pass,
  }
}
