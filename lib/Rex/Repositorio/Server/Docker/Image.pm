#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Image;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use File::Spec;
use File::Path;
use File::Basename 'basename';
require IO::All;
use JSON::XS;

sub put_image {
  my ($self) = @_;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $image_json = File::Spec->catfile( $image_dir, "image.json" );

  mkpath $image_dir;

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

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );

  my @ids = ( $self->param("name") );
  my $parent = readlink File::Spec->catfile( $image_dir, "parent" );
  while ($parent) {
    my $parent_id = basename $parent;
    push @ids, $parent_id;
    $parent = readlink File::Spec->catfile( $image_dir, "..", $parent_id, "parent" );
  }

  $self->render( json => \@ids );
}

sub get_image_layer {
  my ($self) = @_;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $layer_file = File::Spec->catfile( $image_dir, "image.layer" );

  $self->res->headers->add( 'Content-Type', 'application/octet-stream' );

  #$self->render(data => IO::All->new($layer_file)->slurp);
  $self->render_file( filepath => $layer_file );
}

sub get_image {
  my ($self) = @_;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $image_dir =
    File::Spec->catdir( $repo_dir, "images", $self->param("name") );
  my $image_json  = File::Spec->catfile( $image_dir, "image.json" );
  my $chksum_file = File::Spec->catfile( $image_dir, "payload.sha256" );

  if ( -f $image_json ) {
    my $content = IO::All->new($image_json)->slurp;
    my $chksum  = IO::All->new($chksum_file)->slurp;
    $self->res->headers->add( 'X-Docker-Payload-Checksum', $chksum );
    $self->res->headers->add( 'Content-Type',              'application/json' );

    return $self->render( text => $content );
  }

  return $self->render( json => { error => "Image not found" }, status => 404 );
}

1;
