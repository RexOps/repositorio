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
use JSON::XS;
require IO::All;

sub get_repo_images {
  my ($self) = @_;

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $repo_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name );

  my $content =
    IO::All->new( File::Spec->catfile( $repo_dir, "repo.json" ) )->slurp;
  $self->res->headers->add( 'Content-Type', 'application/json' );
  $self->render( text => $content );
}

sub put_repo {
  my ($self) = @_;

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $repo_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name );

  my $ref = decode_json( $self->req->body );
  my $store = [ map { $_ = { id => $_->{id} } } @{$ref} ];

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

  my $repo_name = $self->param("repo_namespace") . "/" . $self->param("name");

  my $tag_dir =
    File::Spec->catdir( $self->app->get_repo_dir( repo => $self->repo->{name} ),
    "repository", $repo_name, "tags" );
  my $ret = {};

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

1;
