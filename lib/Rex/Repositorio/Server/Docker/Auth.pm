#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Auth;

use Mojo::Base 'Mojolicious::Controller';
use MIME::Base64;
use File::Spec;
use File::Path;
use Digest::MD5 'md5_base64';
use Rex::Repositorio::Server::Docker::Helper::Auth;
use JSON::XS;
use Data::Dumper;

# TODO: implement authentication and authorization
#       currently this is just a random string
sub login {
  my ($self) = @_;

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");
  $self->stash(session_changed => 0);

  if ( $self->req->headers->header("Authorization") && $self->stash("session_authenticated") == 0 ) {
    my ($type, $base64_header_line) = split(/ /, $self->req->headers->header("Authorization"), 2);

    if($type eq "Basic") {

      my ( $user, $pass ) = split( /:/, decode_base64( $base64_header_line) );

      my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
      my $user_dir = File::Spec->catdir($repo_dir, "users");

      my $user_o = Rex::Repositorio::Server::Docker::Helper::Auth->create("Plain", {
        user_path => $user_dir,
      });

      $pass = md5_base64($pass);

      if($user_o->login($user, $pass)) {
        my $token = $self->_generate_token;
        $self->stash(session_token => $token);
        $self->stash(session_user => $user);
        $self->stash(session_changed => 1);

        $self->app->log->debug("User: $user logged in.");

        $self->res->headers->add( 'X-Docker-Token' =>
            'Token signature=' . $token . ',repository="' . $repo_name . '",access=write' );
        $self->res->headers->add( 'WWW-Authenticate' =>
            'Token signature=' . $token . ',repository="' . $repo_name . '",access=write' );
      }
      else {
        $self->render(text => 'Access denied', status => 401);
        return 0;
      }
    }
    elsif($type eq "Token") {
        $self->render(text => 'Access denied', status => 401);
        return 0;
    }

  }
  elsif($self->stash("session_authenticated") == 1) {
    # TODO: check if session is valid
    #$self->res->headers->add( "X-Docker-Token" => $self->req->headers->header("X-Docker-Token"));
    #$self->res->headers->add( "WWW-Authenticate" => $self->req->headers->header("WWW-Authenticate"));
    my $user = $self->stash("session_user");
    $self->app->log->debug("User: $user logged in. (via session)");
    my $token = $self->stash("session_token");
    $self->res->headers->add( "X-Docker-Token" =>
        'Token signature=' . $token . ',repository="' . $repo_name . '",access=write' );
    $self->res->headers->add( "WWW-Authenticate" =>
        'Token signature=' . $token . ',repository="' . $repo_name . '",access=write' );
  }

  $self->res->headers->add( 'X-Docker-Endpoints' => $self->req->headers->host );
  $self->res->headers->add( 'Pragma'             => 'no-cache' );
  $self->res->headers->add( 'Expires'            => '-1' );

  1;
}

sub post_user {
  my ($self) = @_;
  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $user_dir = File::Spec->catdir($repo_dir, "users");

  my $ref = $self->req->json;
  my $username = $ref->{username};

  if(! -d File::Spec->catdir($user_dir, $username)) {
    mkpath(File::Spec->catdir($user_dir, $username));

    open(my $fh, ">", File::Spec->catfile($user_dir, $username, "user.json")) or die($!);
    my $ref = $self->req->json;
    $ref->{password} = md5_base64($ref->{password});
    print $fh encode_json($ref);
    close($fh);

    $self->res->headers->add("Content-Type", "application/json");
    return $self->render(text => '"User Created"', status => 201);
  }
  else {
    $self->res->headers->add("Content-Type", "application/json");
    return $self->render(text => '"User Created"', status => 201);
  }
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
