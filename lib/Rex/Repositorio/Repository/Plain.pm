#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Plain;

use Moose;
use Try::Tiny;
use File::Basename qw'basename dirname';
use Data::Dumper;
use Carp;
use Params::Validate qw(:all);
use File::Spec;
use File::Path;
use IO::All;
use JSON::XS;
use Mojo::DOM;

# VERSION

extends "Rex::Repositorio::Repository::Base";

sub mirror {
  my ( $self, %option ) = @_;

  $self->app->print_info("Collecting files. This may take a while...");

  my @dirs = ( $self->repo->{url} );
  my @files;

  for my $dir (@dirs) {
    $dir = "$dir/" if ( $dir !~ m{/$} );
    my $content = $self->download($dir);

    #my $dom     = Mojo::DOM->new($content);
    my @links = ( $content =~ m/<a[^>+]href=["']?([^"'>]+)["'>]/ig );

    $self->app->print_info("Following $dir...");
    $self->app->logger->debug("Following $dir");

    push @dirs, map { "$dir$_" }
      grep { $_ =~ m{/$} }
      grep { $_ !~ m{^\.} } @links;
    push @files, map { "$dir$_" }
      grep { $_ !~ m{/$} } @links;
  }

  my $pr = $self->app->progress_bar(
    title  => "Downloading packages...",
    length => scalar(@files),
  );

  my $i = 0;
  for my $file (@files) {
    $i++;
    $pr->update($i);

    my $path     = $file;
    my $repo_url = $self->repo->{url};
    $path =~ s/$repo_url//g;
    my $local_file = File::Spec->catdir(
      $self->app->get_repo_dir( repo => $self->repo->{name} ),
      $path );
    mkpath basename($local_file);

    $self->download_package(
      url  => $file,
      name => basename($path),
      dest => $local_file,
      cb   => sub {
      },
      force       => $option{force},
      update_file => $option{update_files},
    );
  }
}

sub init {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  mkpath $repo_dir;
}

sub add_file {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      },
    }
  );

  my $dest = File::Spec->catdir($self->app->get_repo_dir( repo => $self->repo->{name} ),
    basename( $option{file} ));

  $self->add_file_to_repo( source => $option{file}, dest => $dest );
}

sub remove_file {
  my $self = shift;

  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      },
    }
  );

  my $file = File::Spec->catdir($self->app->get_repo_dir( repo => $self->repo->{name} ),
     $option{file} );

  $self->remove_file_from_repo( file => $file );
}

1;
