#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Repository;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use File::Spec;
use File::Path;
use File::Basename qw'dirname';
use JSON::XS;
use MIME::Base64;
require IO::All;

# VERSION

sub get_repo_images {
  my ($self) = @_;

  my $requested_file = $self->req->url;
  $self->app->log->debug("Requested-File: $requested_file");
  my $orig_url = $self->repo->{url};
  $orig_url =~ s/\/$//;
  $self->app->log->debug("Upstream-URL: $orig_url");

  $requested_file =~ s/^\///;
  my $orig_file_url = $orig_url . "/" . $requested_file;
  $self->app->log->debug("Orig-File-URL: $orig_file_url");

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $repo_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name );

  my $repo_file = File::Spec->catfile( $repo_dir, "repo.json" );

  if ( -f $repo_file ) {
    my $content = IO::All->new($repo_file)->slurp;
    $self->res->headers->add( 'Content-Type', 'application/json' );
    $self->render( text => $content );
  }
  else {
    my $base64_auth_string = MIME::Base64::encode_base64(
      $self->repo->{upstream_user} . ":" . $self->repo->{upstream_password} );
    $self->proxy_to(
      $orig_file_url,
      sub {
        my ( $c, $tx ) = @_;
        $c->app->log->debug("Got data from upstream...");

        mkpath( dirname($repo_file) );
        open my $fh, '>', $repo_file or die($!);
        binmode $fh;
        print $fh $tx->res->body;
        close $fh;

        my $ref = $tx->res->json;
        my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
        for my $image_data ( @{$ref} ) {
          my $image_dir =
            File::Spec->catdir( $repo_dir, "images", $image_data->{id} );
          mkpath $image_dir;
          open my $image_ep, '>',
            File::Spec->catfile( $image_dir, 'endpoint.data' )
            or die($!);
          print $image_ep $tx->res->headers->header('R-Docker-Endpoints');
          close $image_ep;

          open my $image_lib, '>',
            File::Spec->catfile( $image_dir, 'library.data' )
            or die($!);
          print $image_lib $orig_file_url;
          close $image_lib;
        }

        open my $ep, '>', "$repo_file.endpoint" or die($!);
        print $ep $tx->res->headers->header('R-Docker-Endpoints');
        close $ep;
      },
      sub {
        my ( $c, $tx ) = @_;
        my $docker_token = $tx->res->headers->header('X-Docker-Token') || "";
        $c->app->log->debug("Got my docker token: $docker_token");
        $self->stash( 'upstream_docker_token', $docker_token );

        $self->_fix_docker_headers($tx);
      },
      { # some custom headers to get the docker token, so that we can
         # authenticate against the image servers.
        'X-Docker-Token' => 'true',
        'Authorization'  => "Basic $base64_auth_string",
      },
    );
  }

}

sub put_repo {
  my ($self) = @_;

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $repo_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name );

  my $ref = decode_json( $self->req->body );
  my $store = [ map { { id => $_->{id} } } @{$ref} ];

  mkpath $repo_dir;
  open( my $fh, ">", File::Spec->catfile( $repo_dir, "repo.json" ) ) or die($!);
  print $fh encode_json($store);
  close($fh);

  my $image_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "images", $store->[-1]->{id} );

  #  mkpath $image_dir;
  #  my $ancestor_file = File::Spec->catfile( $image_dir, "ancestors" );
  #
  #  open( my $afh, ">", $ancestor_file ) or die($!);
  #  print $afh encode_json( [ map { $_ = $_->{id} } reverse @{$store} ] );
  #  close($afh);

  #$self->render( json => {}, status => 500 );
  #$self->render( json => {} );
  $self->render( text => '""' );
}

sub get_repo_tag {
  my ($self) = @_;

  my $requested_file = $self->req->url;
  $self->app->log->debug("Requested-File: $requested_file");
  my $orig_url = $self->repo->{url};
  $orig_url =~ s/\/$//;
  $self->app->log->debug("Upstream-URL: $orig_url");

  $requested_file =~ s/^\///;
  my $orig_file_url = $orig_url . "/" . $requested_file;
  $self->app->log->debug("Orig-File-URL: $orig_file_url");

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $tag_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name, "tags" );
  my $ret = {};

  if ( -d $tag_dir ) {
    opendir( my $dh, $tag_dir );
    while ( my $entry = readdir($dh) ) {
      next if ( $entry =~ m/^\./ );
      next if ( !-f File::Spec->catfile( $tag_dir, $entry ) );
      $ret->{$entry} =
        IO::All->new( File::Spec->catfile( $tag_dir, $entry ) )->slurp;
    }
    closedir($dh);

    $self->render( json => $ret );
  }
  else {
    $self->proxy_to(
      $orig_file_url,
      sub {
        my ( $c, $tx ) = @_;
        $c->app->log->debug("Got data from upstream...");
        mkpath $tag_dir;
        my $ref = $tx->res->json;
        for my $e ( @{$ref} ) {
          open my $fh, ">", File::Spec->catfile( $tag_dir, $e->{name} )
            or die($!);
          print $fh $self->_get_image_directory( $e->{layer} );
          close $fh;
        }
      },
      sub {
        # TODO: check why we need to rewrite content
        # must rewrite content... don't know why...
        my ( $c, $tx ) = @_;
        my $content = Mojo::Content::Single->new;
        $content->headers( $tx->res->headers() );
        my $ref     = $tx->res->json;
        my $new_ref = {};
        for my $e ( @{$ref} ) {
          $new_ref->{ $e->{name} } = $self->_get_image_directory( $e->{layer} );
        }

        my $new_content = Mojo::JSON::encode_json($new_ref);
        my $asset       = Mojo::Asset::Memory->new;
        $asset->add_chunk($new_content);
        $content->asset($asset);
        $content->headers->content_length( $asset->size );

        $tx->res->content($content);
      },
      sub {
        my ( $c, $tx ) = @_;
        $self->_fix_docker_headers($tx);
      }
    );
  }
}

sub put_repo_tag {
  my ($self) = @_;

  my $tag_sha = $self->req->body;
  $tag_sha =~ s/"//g;
  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $url = $self->req->url;
  my ($tag_name) = ( $url =~ m/.*\/(.+?)$/ );

  my $tag_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name, "tags" );

  mkpath $tag_dir;
  open( my $fh, ">", File::Spec->catfile( $tag_dir, $tag_name ) ) or die($!);
  print $fh $tag_sha;
  close($fh);

  $self->render( text => 'true' );
}

sub put_repo_image {
  my ($self) = @_;

  $self->render( text => '', status => 204 );
}

sub _get_image_directory {
  my ( $self, $id ) = @_;
  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $images_dir = File::Spec->catdir( $repo_dir, "images" );

  if ( -d File::Spec->catdir( $images_dir, $id ) ) {
    return File::Spec->catdir( $images_dir, $id );
  }

  # try to guess the image directory...
  # TODO: look inside repo.json for better preci... genauigkeit
  opendir( my $dh, $images_dir ) or die($!);
  while ( my $entry = readdir($dh) ) {
    if ( $entry =~ m/^\Q$id\E/ ) {
      return $entry;
    }
  }
  closedir($dh);
}

sub _fix_docker_headers {

  my ( $self, $tx ) = @_;

  my $docker_endpoint = $tx->res->headers->header('X-Docker-Endpoints');
  $tx->res->headers->remove('X-Docker-Endpoints');
  $tx->res->headers->remove('X-Docker-Token');
  $self->app->log->debug("Setting R-Docker-Endpoints to -> $docker_endpoint");
  $tx->res->headers->add( 'R-Docker-Endpoints', $docker_endpoint )
    if $docker_endpoint;

  if ( $self->res->headers->header('WWW-Authenticate') ) {
    $tx->res->headers->add( 'WWW-Authenticate',
      $self->res->headers->header('WWW-Authenticate') );
  }

  if ( $self->res->headers->header('X-Docker-Token') ) {
    $tx->res->headers->add( 'X-Docker-Token',
      $self->res->headers->header('X-Docker-Token') );
  }

  $tx->res->headers->add( 'X-Docker-Endpoints' => $self->req->headers->host );
  $tx->res->headers->add( 'Pragma'             => 'no-cache' );
  $tx->res->headers->add( 'Expires'            => '-1' );

}

1;
