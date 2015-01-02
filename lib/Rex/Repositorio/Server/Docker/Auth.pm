#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Auth;

use Mojo::Base 'Mojolicious::Controller';
use MIME::Base64;

# TODO: implement authentication and authorization
#       currently this is just a random string
sub login {
  my ($self) = @_;

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  if ( $self->req->headers->authorization
    && $self->req->headers->authorization !~ m/^Token/i )
  {
    my ( $user, $pass ) =
      split( /:/, decode_base64( $self->req->headers->authorization ) );
    $self->app->log->debug("User: $user logged in.");
  }

  $self->res->headers->add( 'X-Docker-Token' =>
      'Token signature=' . $self->_generate_token . ',repository="' . $repo_name . '",access=write' );
  $self->res->headers->add( 'WWW-Authenticate' =>
      'Token signature=' . $self->_generate_token . ',repository="' . $repo_name . '",access=write' );
  $self->res->headers->add( 'X-Docker-Endpoints' => 'localhost:3000' );
  $self->res->headers->add( 'Pragma'             => 'no-cache' );
  $self->res->headers->add( 'Expires'            => '-1' );

  1;
}

sub _generate_token {
  my ($self) = @_;

  my @chars = ('a' .. 'z', 0 .. 9);

  srand();
  my $ret = "";
  for ( 1 .. 12 ) {
    $ret .= $chars[ int( rand( scalar(@chars) - 1 ) ) ];
  }

  return $ret;
}

1;
