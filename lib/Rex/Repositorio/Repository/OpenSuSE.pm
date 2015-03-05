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

  my $content = $self->download($self->repo->{url} . "/content");
  my @all_meta_files = $self->_get_yast_directory();

  my %content_sha;
  for my $line (split /\n/, $content) {
    next if ($line !~ m/^(HASH|KEY|META)/);

    my ($type, $sha, $sum, $file) = ($line =~ m/^(HASH|KEY|META)\s*([^\s]+)\s*([^\s]+)\s*(.*)/);
    $content_sha{$file} = $sum;
  }

  for my $file (@all_meta_files) {
    if ($file =~ m/\/$/) {
      # directory
      push @all_meta_files, map { $_ = "$file$_" } $self->_get_yast_directory($file);
    }
  }

  @all_meta_files = grep { ! m/\/$/ } @all_meta_files;

  push @all_meta_files, "suse/repodata/repomd.xml";
  push @all_meta_files, "suse/repodata/repomd.xml.asc";
  push @all_meta_files, "suse/repodata/repomd.xml.key";
  push @all_meta_files, "suse/repodata/appdata.xml";
  push @all_meta_files, "suse/repodata/appdata.xml.gz";

  my $pr = $self->app->progress_bar(
    title  => "Downloading metadata...",
    length => scalar(@all_meta_files),
  );

  my $i = 0;
  for my $file (@all_meta_files) {
    $i++;
    $pr->update($i);

    my $path = $file;
    my $repo_url = $self->repo->{url};
    $path =~ s/$repo_url//g;
    my $local_path = File::Spec->catdir($self->app->get_repo_dir(repo => $self->repo->{name}), dirname($path));
    mkpath $local_path;

    my $local_file = $self->repo->{local} . "/" . $path;

    $self->download_package(
      url  => "$repo_url/$file",
      name => basename($path),
      dest => $local_file,
      cb   => sub {
        my ($dest) = @_;
        if(exists $content_sha{$file}) {
          return $self->_checksum($dest, "sha256", $content_sha{$file});
        }
      },
      force => $option{update_metadata}
    );
  }

  my ($packages_ref, $repomd_ref);
  ($packages_ref, $repomd_ref) = $self->_get_repomd_xml($self->repo->{url} . "/suse/");
  my @packages = map { $_->{location} = "/suse/" . $_->{location}; $_; } @{ $packages_ref };

  $self->_download_packages(\%option, @packages);
}

sub _get_yast_directory {
  my ($self, $url) = @_;
  $url ||= "";
  $self->app->print_info("Reading directory contents: /$url");
  my $content;
  try {
    $content = $self->download( $self->repo->{url} . "/$url/directory.yast" );
  } catch {
    $self->app->logger->debug("No directory.yast found in /$url");
    $content = "";
  };

  return split(/\n/, $content);
}

1;
