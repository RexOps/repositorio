#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Yum;

use Moose;
use Try::Tiny;
use File::Basename qw'basename';
use Data::Dumper;
use Carp;
use Params::Validate qw(:all);
use File::Spec;
use File::Path;
use IO::All;
use JSON::XS;

# VERSION

extends "Rex::Repositorio::Repository::Base";

sub mirror {
  my ( $self, %option ) = @_;

  $self->repo->{url} =~ s/\/$//;
  $self->repo->{local} =~ s/\/$//;
  my $name = $self->repo->{name};

  $self->app->logger->notice("Downloading metadata...");

  my ( $packages_ref, $repomd_ref );
  ( $packages_ref, $repomd_ref ) = $self->_get_repomd_xml( $self->repo->{url} );
  my @packages = @{$packages_ref};

  my $url          = $self->repo->{url} . "/repodata/repomd.xml";
  my $destbase     = $self->app->get_repo_dir(repo => $self->repo->{name});
  my $repodatabase = File::Spec->catfile( $destbase, 'repodata' );

  try {
    $self->download_metadata(
      url   => $url,
      dest  => File::Spec->catfile($repodatabase,'repomd.xml'),
      force => $option{update_metadata},
    );

    $self->app->logger->info("2/3 ${url}");

    $self->download_metadata(
      url   => $url,
      dest  => File::Spec->catfile($repodatabase,'repomd.xml'),
      force => $option{update_metadata},
    );

    $self->app->logger->info("3/3 ${url}");
  }
  catch {
    $self->app->logger->info("3/3 ${url}");
    $self->app->logger->error($_);
  };

  $self->app->logger->notice('Downloading packages...');
  $self->_download_packages( \%option, @packages );

  $self->app->logger->notice('Downloading rest of metadata...');

  my $m_count = 0;
  my $m_total = scalar(@{$repomd_ref->{data}});

  for my $file_data ( @{ $repomd_ref->{data} } ) {

    my $file_url =
      $self->{repo}->{url} . "/" . $file_data->{location}->[0]->{href};
    my $file = basename $file_data->{location}->[0]->{href};

    $m_count++;
    $self->app->logger->info("${m_count}/$m_total ${file_url}");

    $self->download_metadata(
      url  => $file_url,
      dest => File::Spec->catfile($repodatabase,$file),
      cb   => sub {
        $self->_checksum(
          @_,
          $file_data->{checksum}->[0]->{type},
          $file_data->{checksum}->[0]->{content}
        );
      },
      force => $option{update_metadata},
    );
  }

  if ( exists $self->repo->{images} && $self->repo->{images} eq "true" ) {

    $self->app->logger->notice('Downloading images...');
    my @files = (
        "images/boot.iso",           "images/efiboot.img",
        "images/efidisk.img",        "images/install.img",
        "images/pxeboot/initrd.img", "images/pxeboot/vmlinuz",
        "images/upgrade.img",        "LiveOS/squashfs.img",
    );
    my $file_count = 0;
    my $file_total = scalar @files;

    for my $file (@files) {
      my $file_url   = $self->repo->{url} . "/" . $file;
      my $local_file = File::Spec->catfile($destbase, $file);

      $file_count++;
      $self->app->logger->info("${file_count}/$file_total ${file_url}");

      try {
        $self->download_package(
          url  => $file_url,
          name => $file,
          dest => $local_file,
        );
        1;
      }
      catch {
        $self->app->logger->error("Error downloading ${file_url}.");
      };
    }
  }
}

sub _download_packages {
  my ( $self, $_option, @packages ) = @_;

  if ( !$_option->{update_files} && !$_option->{force} ) {
    return;
  }

  my %option = %{$_option};

  my $p_count = 0;
  my $p_total = scalar @packages;

  my $destbase = $self->app->get_repo_dir(repo => $self->repo->{name});

  for my $package (@packages) {
    my $package_url  = $self->repo->{url} . "/" . $package->{location};
    my $package_name = $package->{name};

    $p_count++;
    $self->app->logger->info("${p_count}/$p_total ${package_url}");
    my $local_file = File::Spec->catfile($destbase,$package->{location});

    my ($type, $value);
    if ($option{'checksums'}) {
      $type = $package->{checksum}->{type};
      $value = $package->{checksum}->{data};
    }
    else {
      $type = 'size';
      $value = $package->{size};
    }

    $self->download_package(
      url  => $package_url,
      name => $package_name,
      dest => $local_file,
      cb   => sub {
        $self->_checksum(
          @_,
          $type,
          $value,
        );
      },
      update_file => $option{update_files},
      force       => $option{force},
    );
  }
}

sub _get_repomd_xml {
  my ( $self, $url ) = @_;

  my $repomd_ref =
    $self->decode_xml( $self->download("${url}/repodata/repomd.xml") );

  my ($primary_file) =
    grep { $_->{type} eq "primary" } @{ $repomd_ref->{data} };
  $primary_file = $primary_file->{location}->[0]->{href};

  $url = $url . "/" . $primary_file;
  my $xml = $self->get_xml( $self->download_gzip($url) );

  my @packages;
  my @xml_packages = $xml->getElementsByTagName('package');
  for my $xml_package (@xml_packages) {
    my ($name_node)     = $xml_package->getChildrenByTagName("name");
    my ($checksum_node) = $xml_package->getChildrenByTagName("checksum");
    my ($size_node)     = $xml_package->getChildrenByTagName("size");
    my ($location_node) = $xml_package->getChildrenByTagName("location");
    push @packages, {
      location => $location_node->getAttribute("href"),
      name     => $name_node->textContent,
      checksum => {
        type => $checksum_node->getAttribute("type"),
        data => $checksum_node->textContent,
      },
      size => $size_node->getAttribute('package'),
    };
  }

  return ( \@packages, $repomd_ref );
}

sub init {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir(repo => $self->repo->{name});
  my $repodata_path = File::Spec->catdir($repo_dir, 'repodata');
  $self->app->logger->debug("init: repodata_path: ${repodata_path}");
  unless (-d $repodata_path) {
    $self->app->logger->debug("init: make_path: ${repodata_path}");
    my $make_path_error;
    #my $dirs = File::Path->make_path($repodata_path, { error => \$make_path_error },);
    #my $dirs = File::Path->make_path($repodata_path);
    unless (File::Path->make_path($repodata_path)) {
      $self->app->logger->log_and_croak(level => 'error', message => "init: unable to create path: ${repodata_path}");
    }
  }

  $self->_run_createrepo();
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

  my $dest = File::Spec->catfile($self->app->get_repo_dir(repo => $self->repo->{name}), basename( $option{file} ));

  $self->add_file_to_repo( source => $option{file}, dest => $dest );

  $self->_run_createrepo();
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

  my $file = File::Spec->catfile($self->app->get_repo_dir(repo => $self->repo->{name}), basename( $option{file} ));

  $self->remove_file_from_repo( file => $file );

  $self->_run_createrepo();
}

sub _run_createrepo {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir(repo => $self->repo->{name});

  if ( exists $self->repo->{gpg} && $self->repo->{gpg}->{key} ) {
    unlink File::Spec->catfile($repo_dir, qw/ repodata repomd.xml.asc /);
  }

  system "cd $repo_dir ; createrepo .";
  if ( $? != 0 ) {
    confess "Error running createrepo.";
  }

  if ( exists $self->repo->{gpg} && $self->repo->{gpg}->{key} ) {
    my $key  = $self->repo->{gpg}->{key};
    my $pass = $self->repo->{gpg}->{password};
    if ( !$pass ) {
      $pass = $self->read_password("GPG key passphrase: ");
    }

    my $cmd =
        "cd $repo_dir ; gpg --default-key $key -a --batch --passphrase '"
      . $pass
      . "' --detach-sign repodata/repomd.xml";
    system $cmd;

    if ( $? != 0 ) {
      $cmd =~ s/\Q$pass\E/\*\*\*\*\*\*\*/;
      confess "Error running: $cmd";
    }

    # export pub key as asc file
    my $pub_file = $self->repo->{name} . ".asc";
    $cmd = "cd $repo_dir ; gpg -a --output $pub_file --export $key";
    system $cmd;

    if ( $? != 0 ) {
      confess "Error running gpg export: $cmd";
    }
  }
}

# test if all necessary parameters are available
override verify_options => sub {
  my $self = shift;
  super();

  if ( !exists $self->repo->{local} ) {
    confess "No local path (local) given for: " . $self->repo->{name};
  }
};

1;
