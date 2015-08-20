#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::OpenSuSE;

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

# VERSION

extends "Rex::Repositorio::Repository::Yum";

sub mirror {
  my ( $self, %option ) = @_;

  $self->repo->{url} =~ s/\/$//;
  $self->repo->{local} =~ s/\/$//;
  my $name = $self->repo->{name};

  $self->app->print_info("Downloading repository information...");

  my $content  = $self->download( $self->repo->{url} . "/content" );
  my $desc_dir = "suse/setup/descr";
  my $data_dir = "suse";

  for my $line ( split( /\n/, $content ) ) {
    if ( $line =~ m/^DESCRDIR/ ) {
      my $_t;
      ( $_t, $desc_dir ) = split( /\s+/, $line );
      last;
    }
  }
  $self->app->logger->debug("Found descr dir: $desc_dir");

  for my $line ( split( /\n/, $content ) ) {
    if ( $line =~ m/^DATADIR/ ) {
      my $_t;
      ( $_t, $data_dir ) = split( /\s+/, $line );
      last;
    }
  }
  $self->app->logger->debug("Found data dir: $data_dir");

  my @all_meta_files = $self->_get_yast_directory();
  push @all_meta_files, $self->_get_yast_directory($desc_dir);

  my %content_sha;
  for my $line ( split /\n/, $content ) {
    next if ( $line !~ m/^(HASH|KEY|META)/ );

    my ( $type, $sha, $sum, $file ) =
      ( $line =~ m/^(HASH|KEY|META)\s*([^\s]+)\s*([^\s]+)\s*(.*)/ );
    $content_sha{$file} = $sum;
  }

  for my $file (@all_meta_files) {
    if ( $file =~ m/\/$/ ) {

      # directory
      push @all_meta_files, $self->_get_yast_directory($file);
    }
  }

  @all_meta_files = grep { !m/\/$/ } @all_meta_files;

  push @all_meta_files, "$data_dir/repodata/repomd.xml";
  push @all_meta_files, "$data_dir/repodata/repomd.xml.asc";
  push @all_meta_files, "$data_dir/repodata/repomd.xml.key";
  push @all_meta_files, "$data_dir/repodata/appdata.xml";
  push @all_meta_files, "$data_dir/repodata/appdata.xml.gz";

  my $pr = $self->app->progress_bar(
    title  => "Downloading metadata...",
    length => scalar(@all_meta_files),
  );

  my $i = 0;
  for my $file (@all_meta_files) {
    $i++;
    $pr->update($i);

    my $path     = $file;
    my $repo_url = $self->repo->{url};
    $path =~ s/$repo_url//g;
    my $local_file = File::Spec->catdir(
      $self->app->get_repo_dir( repo => $self->repo->{name} ),
      $path );
    make_path dirname($local_file);

    $self->download_package(
      url  => "$repo_url/$file",
      name => basename($path),
      dest => $local_file,
      cb   => sub {
        my ($dest) = @_;
        if ( exists $content_sha{$file} ) {
          return $self->_checksum( $dest, "sha256", $content_sha{$file} );
        }
      },
      force => $option{update_metadata}
    );
  }

  my ( $packages_ref, $repomd_ref );
  ( $packages_ref, $repomd_ref ) =
    $self->_get_repomd_xml( $self->repo->{url} . "/$data_dir/" );
  my @packages = map { $_->{location} = "/$data_dir/" . $_->{location}; $_; }
    @{$packages_ref};

  $self->_download_packages( \%option, @packages );
}

sub _get_yast_directory {
  my ( $self, $url ) = @_;
  $url ||= "";
  $self->app->print_info("Reading directory contents: /$url");
  my $content;
  try {
    $content = $self->download( $self->repo->{url} . "/$url/directory.yast" );
  }
  catch {
    $self->app->logger->debug("No directory.yast found in /$url");
    $content = "";
  };

  my @data;
  for my $line ( split( /\n/, $content ) ) {
    if ($url) {
      push @data, "$url/$line";
    }
    else {
      push @data, $line;
    }
  }

  return @data;
}

1;
