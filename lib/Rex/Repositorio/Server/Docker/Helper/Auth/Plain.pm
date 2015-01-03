#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Helper::Auth::Plain;

use Moose;
use File::Spec;
use JSON::XS;
require IO::All;

has user_path => (is => 'ro');

sub login {
  my ($self, $user, $password) = @_;

  my $user_dir = File::Spec->catdir($self->user_path, $user);
  my $user_file = File::Spec->catfile($user_dir, "user.json");

  if(! -f $user_file) {
    return 0;
  }

  my $user_ref = decode_json(IO::All->new($user_file)->slurp);

  if($user_ref->{password} eq $password) {
    return 1;
  }

  return 0;
}

1;
