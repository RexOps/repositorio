#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Search;

use Mojo::Base 'Mojolicious::Controller';

sub search {
  my ($self) = @_;

  my $ret = {
    num_results => 1,
    query       => "rex",
    results     => [
      {
        description => "desc",
        name        => "foo/rex",
      }
    ]
  };

  $self->render( json => $ret );
}

1;
