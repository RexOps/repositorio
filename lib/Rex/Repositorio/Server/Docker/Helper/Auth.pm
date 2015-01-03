#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Helper::Auth;

use strict;
use warnings;

sub create {
  my ($class, $type, $config) = @_;
  my $auth_class = "Rex::Repositorio::Server::Docker::Helper::Auth::$type";
  eval "use $auth_class;";
  if($@) {
    die "Error finding auth class: $auth_class.";
  }
  my $klass = $auth_class->new(%{ $config });
  return $klass;
}

1;
