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

extends "Rex::Repositorio::Repository::Base";

sub mirror {
  my ( $self, %option ) = @_;

  $self->repo->{url} =~ s/\/$//;
  $self->repo->{local} =~ s/\/$//;
  my $name = $self->repo->{name};

  my $repomd_ref =
    $self->decode_xml(
    $self->download( $self->repo->{url} . "/repodata/repomd.xml" ) );

  my ($primary_file) =
    grep { $_->{type} eq "primary" } @{ $repomd_ref->{data} };
  $primary_file = $primary_file->{location}->[0]->{href};

  my $url = $self->repo->{url} . "/" . $primary_file;
  $self->app->logger->debug("Downloading $url.");
  my $xml = $self->get_xml( $self->download_gzip($url) );

  my @packages;
  my @xml_packages = $xml->getElementsByTagName('package');
  for my $xml_package (@xml_packages) {
    my ($name_node)     = $xml_package->getChildrenByTagName("name");
    my ($checksum_node) = $xml_package->getChildrenByTagName("checksum");
    my ($size_node)     = $xml_package->getChildrenByTagName("size");
    my ($location_node) = $xml_package->getChildrenByTagName("location");
    push @packages,
      {
      location => $location_node->getAttribute("href"),
      name     => $name_node->textContent,
      checksum => {
        type => $checksum_node->getAttribute("type"),
        data => $checksum_node->textContent,
      },
      size => $size_node->getAttribute("archive"),
      };
  }

  for my $package (@packages) {
    my $package_url  = $self->repo->{url} . "/" . $package->{location};
    my $package_name = $package->{name};

    my $local_file = $self->repo->{local} . "/" . $package->{location};
    $self->download_package(
      url  => $package_url,
      name => $package_name,
      dest => $local_file,
      cb   => sub {
        $self->_checksum(
          @_,
          $package->{checksum}->{type},
          $package->{checksum}->{data}
        );
      },
      force => $option{update_files}
    );
  }

  try {
    $self->download_metadata(
      url   => $self->repo->{url} . "/repodata/repomd.xml",
      dest  => $self->repo->{local} . "/repodata/repomd.xml",
      force => $option{update_metadata},
    );

    $self->download_metadata(
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

    $self->download_metadata(
      url  => $file_url,
      dest => $self->repo->{local} . "/repodata/$file",
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
    for my $file (
      (
        "images/boot.iso",           "images/efiboot.img",
        "images/efidisk.img",        "images/install.img",
        "images/pxeboot/initrd.img", "images/pxeboot/vmlinuz",
        "images/upgrade.img",
      )
      )
    {
      my $file_url   = $self->repo->{url} . "/" . $file;
      my $local_file = $self->repo->{local} . "/" . $file;
      try {
        $self->download_package(
          url  => $file_url,
          name => $file,
          dest => $local_file,
        );
        1;
      }
      catch {
        $self->app->logger->error("Error downloading $file_url.");
      };
    }
  }
}

sub init {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  mkpath "$repo_dir/repodata";

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

  my $dest = $self->app->get_repo_dir( repo => $self->repo->{name} ) . "/"
    . basename( $option{file} );

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

  my $file = $self->app->get_repo_dir( repo => $self->repo->{name} ) . "/"
    . basename( $option{file} );

  $self->remove_file_from_repo( file => $file );

  $self->_run_createrepo();
}

sub _run_createrepo {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );

  if ( exists $self->repo->{gpg} && $self->repo->{gpg}->{key} ) {
    unlink "$repo_dir/repodata/repomd.xml.asc";
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
