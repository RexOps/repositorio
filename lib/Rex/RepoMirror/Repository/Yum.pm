#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::RepoMirror::Repository::Yum;

use Moo;
use Try::Tiny;
use File::Basename qw'basename';
use Data::Dumper;
use Digest::SHA;
use Carp;

extends "Rex::RepoMirror::Repository::Base";

sub mirror {
  my ( $self, %option ) = @_;

  $self->repo->{url} =~ s/\/$//;
  $self->repo->{local} =~ s/\/$//;

  my $repomd_ref =
    $self->app->decode_xml(
    $self->app->download( $self->repo->{url} . "/repodata/repomd.xml" ) );

  my ($primary_file) =
    map { $_ = $_->{location}->[0]->{href} }
    grep { $_->{type} eq "primary" } @{ $repomd_ref->{data} };

  my $url = $self->repo->{url} . "/" . $primary_file;
  $self->app->logger->debug("Downloading $url.");
  my $ref = $self->app->decode_xml( $self->app->download_gzip($url) );
  for my $package ( @{ $ref->{package} } ) {
    my $package_url =
      $self->repo->{url} . "/" . $package->{location}->[0]->{href};
    my $package_name = $package->{name}->[0];

    my $local_file = $self->repo->{local} . "/" . basename($package_url);
    $self->app->download_package(
      url  => $package_url,
      name => $package_name,
      dest => $local_file,
      cb   => sub {
        $self->_checksum( @_, $package->{checksum}->[0]->{content} );
      },
      force => $option{update_files}
    );
  }

  try {
    $self->app->download_metadata(
      url   => $self->repo->{url} . "/repodata/repomd.xml",
      dest  => $self->repo->{local} . "/repodata/repomd.xml",
      force => $option{update_metadata},
    );

    $self->app->download_metadata(
      url   => $self->repo->{url} . "/repodata/repomd.xml.asc",
      dest  => $self->repo->{local} . "/repodata/repomd.xml.asc",
      force => $option{update_metadata},
    );
  }
  catch {
    $self->app->logger->error($_);
  };

  for my $file_data ( @{ $repomd_ref->{data} } ) {
    my $file_url =
      $self->{repo}->{url} . "/" . $file_data->{location}->[0]->{href};
    my $file = basename $file_data->{location}->[0]->{href};

    $self->app->download_metadata(
      url  => $file_url,
      dest => $self->repo->{local} . "/repodata/$file",
      cb   => sub {
        $self->_checksum( @_, $file_data->{checksum}->[0]->{content} );
      },
      force => $option{update_metadata},
    );
  }
}

sub _checksum {
  my ( $self, $file, $wanted_checksum ) = @_;
  my $sha = Digest::SHA->new(1);
  $sha->addfile($file);
  my $file_checksum = $sha->hexdigest;

  $self->app->logger->debug(
    "wanted_checksum: $wanted_checksum == $file_checksum");

  if ( $wanted_checksum ne $file_checksum ) {
    $self->app->logger->error("Checksum for $file wrong.");
    confess "Checksum of $file wrong.";
  }
}

1;
