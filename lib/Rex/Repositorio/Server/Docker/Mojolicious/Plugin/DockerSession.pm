#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Mojolicious::Plugin::DockerSession;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Plugin';
use Data::Dumper;
use File::Spec;
use File::Path;
use JSON::XS;
require IO::All;

sub register {
  my ( $self, $app ) = @_;

  my $session_dir = File::Spec->catdir(
    $app->get_repo_dir( repo => $app->repo->{name} ), "_sessions" );

  $app->hook(
    before_dispatch => sub {
      my ( $self, $c ) = @_;
      $app->log->debug("before_dispatch: DockerSession");
      $self->stash("session_authenticated", 0);

      if ( $self->req->headers->header("Authorization") ) {
        my ($type, $base64_header_line) = split(/ /, $self->req->headers->header("Authorization"), 2);
        if($type eq "Token") {
          my ($session_id) = ($base64_header_line =~ m/signature=([^,]+),/);
          my $session_file = File::Spec->catfile($session_dir, $session_id);
          if($session_id && -f $session_file) {
            my $ref = decode_json(IO::All->new($session_file)->slurp);
            $self->stash("session_token", $session_id);
            $self->stash("session_user", $ref->{user});
            $self->stash("session_authenticated", 1);
          }
        }
      }
    },
  );

  $app->hook(
    after_dispatch => sub {
      my ( $self, $c ) = @_;
      $app->log->debug("after_dispatch: DockerSession");

      if($self->stash->{session_changed}) {
        my $session_file =
          File::Spec->catfile( $session_dir, $self->stash->{session_token} );

        if ( !-d $session_dir ) {
          mkpath $session_dir;
        }

        open( my $fh, ">", $session_file ) or die($!);
        print $fh encode_json(
          {
            token => $self->stash->{session_token},
            user  => $self->stash->{session_user}
          }
        );
        close($fh);
      }
    },
  );
}

1;
