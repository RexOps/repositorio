#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Image;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use File::Spec;
use File::Path 'make_path', 'remove_tree';
use File::Basename 'basename';
require IO::All;
use JSON::XS;
use MIME::Base64;

# VERSION

sub put_image {
  my ($self) = @_;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $image_json = File::Spec->catfile( $image_dir, "image.json" );

  make_path $image_dir;

  open( my $fh, ">", $image_json ) or die($!);
  print $fh $self->req->body;
  close($fh);

  eval {
    my $ref = decode_json $self->req->body;
    if ( exists $ref->{parent} ) {
      symlink File::Spec->catfile( $repo_dir, "images", $ref->{parent} ),
        File::Spec->catfile( $image_dir, 'parent' );
    }
    1;
  } or do {
    print STDERR ">> ERR> $@\n";
  };

  $self->render( text => "true" );
}

sub put_image_layer {
  my ($self) = @_;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $image_layer = File::Spec->catfile( $image_dir, "image.layer" );

  my $chunk = $self->req->body;

  open( my $fh, ">", $image_layer ) or die($!);
  print $fh $chunk;
  close($fh);

  $self->render( text => 'true' );
}

# TODO: implement checksuming
sub put_image_checksum {
  my ($self) = @_;

  my $name = $self->param("name");

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $chksum_file = File::Spec->catfile( $image_dir, "payload.sha256" );

  #print STDERR "($name) got chksum> "
  #  . $self->req->headers->header('X-Docker-Checksum') . "\n";
  #print STDERR "($name) got chksum payload> "
  #  . $self->req->headers->header('X-Docker-Checksum-Payload') . "\n";

  open( my $fh, ">", $chksum_file ) or die($!);
  print $fh $self->req->headers->header('X-Docker-Checksum-Payload');
  close($fh);

  $self->render( text => 'true' );
}

sub get_image_ancestry {
  my ($self) = @_;

  my $requested_file = $self->req->url;
  $self->app->log->debug("Requested-File: $requested_file");
  my $orig_url = $self->repo->{url};
  $orig_url =~ s/\/$//;
  $self->app->log->debug("Upstream-URL: $orig_url");

  $requested_file =~ s/^\///;
  my $orig_file_url = $orig_url . "/" . $requested_file;
  $self->app->log->debug("Orig-File-URL: $orig_file_url");

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );

  my @ids = ( $self->param("name") );
  my $parent_id_file = File::Spec->catfile( $image_dir, "parent" );
  if ( -l $parent_id_file ) {
    my $parent = readlink $parent_id_file;
    while ($parent) {
      my $parent_id = basename $parent;
      push @ids, $parent_id;
      $parent =
        readlink File::Spec->catfile( $image_dir, "..", $parent_id, "parent" );
    }

    $self->render( json => \@ids );
  }
  else {
    $self->_auth_upstream();
    my $upstream_file = File::Spec->catfile( $image_dir, "endpoint.data" );
    $self->app->log->debug("Looking for upstream file: $upstream_file");
    if ( -f $upstream_file ) {
      my ($upstream_host) = eval { local (@ARGV) = ($upstream_file); <>; };
      $orig_file_url =~ s"^(http|https)://([^/]+)/"$1://$upstream_host/";
      $self->app->log->debug("Rewrite Upstream-URL: $orig_file_url");
    }

    $self->proxy_to(
      $orig_file_url,
      sub {
        my ( $c, $tx ) = @_;
        $c->app->log->debug("Got data from upstream...");
        $c->app->log->debug("Writing ancestry (parent) file: $parent_id_file");
        my $ref = $tx->res->json;
        my @ids = @{$ref};
        shift @ids; # first one is the directory itself.
        my $child_dir = File::Spec->catfile( $image_dir, "parent" );
        for my $parent_id (@ids) {
          my $link_target =
            File::Spec->catdir( $repo_dir, "images", $parent_id );
          my $link_name = $child_dir;
          symlink $link_target, $link_name;

          $child_dir = File::Spec->catfile( $link_target, "parent" );
        }
      },
      sub {
        my ( $c, $tx ) = @_;
        $self->_fix_docker_headers($tx);
      },
      {
        'Authorization' => 'Token ' . $self->stash('upstream_docker_token'),
      }
    );
  }
}

sub get_image_layer {
  my ($self) = @_;

  my $requested_file = $self->req->url;
  $self->app->log->debug("Requested-File: $requested_file");
  my $orig_url = $self->repo->{url};
  $orig_url =~ s/\/$//;
  $self->app->log->debug("Upstream-URL: $orig_url");

  $requested_file =~ s/^\///;
  my $orig_file_url = $orig_url . "/" . $requested_file;
  $self->app->log->debug("Orig-File-URL: $orig_file_url");

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $layer_file = File::Spec->catfile( $image_dir, "image.layer" );
  $self->app->log->debug("Layer-File: $layer_file");

  if ( -f $layer_file ) {
    $self->res->headers->add( 'Content-Type', 'application/octet-stream' );

    #$self->render(data => IO::All->new($layer_file)->slurp);
    $self->render_file( filepath => $layer_file );
  }
  else {
    $self->_auth_upstream();
    my $upstream_file = File::Spec->catfile( $image_dir, "endpoint.data" );
    $self->app->log->debug("Looking for upstream file: $upstream_file");
    if ( -f $upstream_file ) {
      my ($upstream_host) = eval { local (@ARGV) = ($upstream_file); <>; };
      $orig_file_url =~ s"^(http|https)://([^/]+)/"$1://$upstream_host/";
      $self->app->log->debug("Rewrite Upstream-URL: $orig_file_url");
    }

    $self->proxy_to(
      $orig_file_url,
      sub {
        my ( $c, $tx ) = @_;
        $c->app->log->debug("Got data from upstream...");
        $c->app->log->debug("Writing layer file: $layer_file");
        open my $fh, '>', $layer_file or die($!);
        binmode $fh;
        print $fh $tx->res->body;
        close $fh;
      },
      sub {
        my ( $c, $tx ) = @_;
        $self->_fix_docker_headers($tx);
      },
      {
        'Authorization' => 'Token ' . $self->stash('upstream_docker_token'),
      }
    );
  }
}

sub get_image {
  my ($self) = @_;

  my $requested_file = $self->req->url;
  $self->app->log->debug("Requested-File: $requested_file");
  my $orig_url = $self->repo->{url};
  $orig_url =~ s/\/$//;
  $self->app->log->debug("Upstream-URL: $orig_url");

  $requested_file =~ s/^\///;
  my $orig_file_url = $orig_url . "/" . $requested_file;
  $self->app->log->debug("Orig-File-URL: $orig_file_url");

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  $self->app->log->debug("Found image directory: $image_dir");

  my $image_json  = File::Spec->catfile( $image_dir, "image.json" );
  my $chksum_file = File::Spec->catfile( $image_dir, "payload.sha256" );

  if ( -f $image_json ) {
    my $content = IO::All->new($image_json)->slurp;
    my $chksum  = IO::All->new($chksum_file)->slurp;
    $self->res->headers->add( 'X-Docker-Payload-Checksum', $chksum );
    $self->res->headers->add( 'Content-Type',              'application/json' );

    return $self->render( text => $content );
  }
  else {
    $self->_auth_upstream();
    my $upstream_file = File::Spec->catfile( $image_dir, "endpoint.data" );
    $self->app->log->debug("Looking for upstream file: $upstream_file");
    if ( -f $upstream_file ) {
      my ($upstream_host) = eval { local (@ARGV) = ($upstream_file); <>; };
      $orig_file_url =~ s"^(http|https)://([^/]+)/"$1://$upstream_host/";
      $self->app->log->debug("Rewrite Upstream-URL: $orig_file_url");
    }

    $self->proxy_to(
      $orig_file_url,
      sub {
        my ( $c, $tx ) = @_;
        $c->app->log->debug("Got data from upstream...");
        open my $fh, '>', $image_json or die($!);
        print $fh $tx->res->body;
        close $fh;

        open my $fh_p, '>', $chksum_file or die($!);
        print $fh_p $tx->res->headers->header('X-Docker-Payload-Checksum');
        close $fh_p;
      },
      sub {
        my ( $c, $tx ) = @_;
        $self->_fix_docker_headers($tx);
      },
      {
        'Authorization' => 'Token ' . $self->stash('upstream_docker_token'),
      }
    );
  }

 #return $self->render( json => { error => "Image not found" }, status => 404 );
}

sub _fix_docker_headers {

  my ( $self, $tx ) = @_;

  my $docker_endpoint = $tx->res->headers->header('X-Docker-Endpoints');
  $tx->res->headers->remove('X-Docker-Endpoints');
  $tx->res->headers->remove('X-Docker-Token');
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

sub _auth_upstream {
  my ($self) = @_;
  my $docker_token = $self->stash('upstream_docker_token');
  if ($docker_token) {
    $self->app->log->debug("Docker Token: $docker_token");
  }
  else {
    $self->app->log->debug("Docker Token: no token found in session.");
    $self->app->log->debug("Need to authenticate on upstream docker registry.");

    my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
    my $image_dir =
      File::Spec->catdir( $repo_dir, "images", $self->param("name") );
    my $library = File::Spec->catfile( $image_dir, "library.data" );
    if ( !-f $library ) {
      $self->app->log->error("Can't find upstream library url.");
      die "Error finding upstream library url.";
    }
    my $registry_url = IO::All->new($library)->slurp;
    $self->app->log->debug("Got upstream registry url: $registry_url");

    my $base64_auth_string = MIME::Base64::encode_base64(
      $self->repo->{upstream_user} . ":" . $self->repo->{upstream_password} );

 # need to create a new object, so there is no cookies from proxy requests in it
    my $ua = Mojo::UserAgent->new;
    $ua->max_redirects(5);

    if ( $self->repo->{ca} ) {
      $ua->ca( $self->repo->{ca} );
    }
    if ( $self->repo->{key} ) {
      $ua->key( $self->repo->{key} );
    }
    if ( $self->repo->{cert} ) {
      $ua->cert( $self->repo->{cert} );
    }

    my $tx = $ua->get(
      $registry_url,

      { # some custom headers to get the docker token, so that we can
         # authenticate against the image servers.
        'X-Docker-Token' => 'true',
        'Authorization'  => "Basic $base64_auth_string",
      },

    );

    if ( $tx->success ) {
      my $docker_token = $tx->res->headers->header('X-Docker-Token') || "";
      if ( !$docker_token ) {
        $self->app->log->error(
          "Authentication successfull but can't find a token.");
        $self->app->log->debug( Dumper($tx) );
      }
      $self->app->log->debug("Got my docker token: $docker_token");
      $self->stash( 'upstream_docker_token', $docker_token );
    }
    else {
      $self->app->log->error(
        "Can't authenticate to upstream docker registry: $registry_url");
    }
  }
}

1;
