#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Apt;

use Moose;
use Try::Tiny;
use File::Basename qw'basename';
use Data::Dumper;
use Digest::SHA;
use Carp;
use Params::Validate qw(:all);
use File::Spec;
use File::Path;
use IO::All;

extends "Rex::Repositorio::Repository::Base";

sub mirror {
  my ( $self, %option ) = @_;

  $self->repo->{url} =~ s/\/$//;
  $self->repo->{local} =~ s/\/$//;
  my $name = $self->repo->{name};

  my $dist = $self->repo->{dist};

  my @archs = split /, ?/, $self->repo->{arch};

  ##############################################################################
  # get meta data
  ##############################################################################
  my $url      = $self->repo->{url} . "/dists/$dist";
  my $contents = $self->download("$url/Release");
  my $ref      = $self->_parse_debian_release_file($contents);

  for my $file_data ( @{ $ref->{SHA1} } ) {
    my $file_url = $url . "/" . $file_data->{file};
    my $file     = $file_data->{file};

    $self->download_metadata(
      url  => $file_url,
      dest => $self->repo->{local} . "/dists/$dist/$file",
      cb   => sub {
        if ( $file eq "Release" ) { return; }

        $self->_checksum( @_, "sha1", $file_data->{checksum} );
      },
      force => $option{update_metadata},
    );

  }

  ##############################################################################
  # download packages
  ##############################################################################
  my @components = split /, ?/, $self->repo->{components};
  for my $component (@components) {

    my $local_components_path =
      $self->app->get_repo_dir( repo => $self->repo->{name} )
      . "/dists/$dist/$component";

    for my $arch (@archs) {
      $self->app->logger->debug("Processing ($name, $component) $dist / $arch");

      my $local_packages_path =
        $local_components_path . "/binary-$arch/Packages";

      $self->app->logger->debug("Reading: $local_packages_path");
      my $content     = io($local_packages_path)->slurp;
      my $package_ref = $self->_parse_debian_package_file($content);

      for my $package ( @{$package_ref} ) {
        my $package_url  = $self->repo->{url} . "/" . $package->{Filename};
        my $package_name = $package->{Package};

        my $local_file = $self->repo->{local} . "/" . $package->{Filename};
        $self->download_package(
          url  => $package_url,
          name => $package_name,
          dest => $local_file,
          cb   => sub {
            $self->_checksum( @_, "sha1", $package->{SHA1} );
          },
          force => $option{update_files}
        );
      }
    }
  }

  ##############################################################################
  # download rest of metadata
  ##############################################################################
  for my $arch (@archs) {
    for my $suffix (qw/bz2 gz/) {
      my $file_url = $url . "/Contents-$arch.$suffix";
      my $file     = "Contents-$arch.$suffix";

      try {
        $self->download_metadata(
          url   => $file_url,
          dest  => $self->repo->{local} . "/dists/$dist/$file",
          force => $option{update_metadata},
        );
      }
      catch {
        $self->app->logger->error($_);
      };
    }
  }

}

sub _parse_debian_release_file {
  my ( $self, $content ) = @_;

  my $ret     = {};
  my $section = "main";
  for my $line ( split /\n/, $content ) {
    chomp $line;
    next if ( $line =~ m/^\s*?$/ );

    if ( $line !~ m/^\s/ ) {
      my ( $key, $value ) = split /:/, $line;
      $value =~ s/^\s*|\s*$//;
      $section = $key;
      if ($value) {
        $ret->{$key} = $value;
      }
      else {
        $ret->{$key} = [];
      }
    }

    if ( $line =~ m/^\s/ ) {
      $line =~ s/^\s//;
      my @values = split /\s+/, $line;
      if ( $ret->{$section} && !ref $ret->{$section} ) {
        $ret->{$section} = [ $ret->{$section} ];
      }
      push @{ $ret->{$section} },
        {
        checksum => $values[0],
        size     => $values[1],
        file     => $values[2],
        };
    }
  }

  return $ret;
}

sub _parse_debian_package_file {
  my ( $self, $content ) = @_;

  my @ret;

  my $section;
  my $current_section;
  for my $line ( split /\n/, $content ) {
    chomp $line;

    if ( $line =~ m/^$/ ) {
      push @ret, $current_section;
      $current_section = {};
      next;
    }

    my ( $key, $value ) = ( $line =~ m/^([A-Z0-9a-z\-]+):(.*)$/ );

    if ($key) {
      $value =~ s/^\s//;
      $section = $key;
      $current_section->{$key} = $value;
    }
    else {
      $value = $line;
      $value =~ s/^\s//;

      if ( $current_section->{$section} && !ref $current_section->{$section} ) {
        $current_section->{$section} = [ $current_section->{$section} ];
      }

      push @{ $current_section->{$section} }, $value;
    }
  }

  return \@ret;
}

1;

__END__

Package: rex
Priority: optional
Section: admin
Installed-Size: 1101
Maintainer: jan gehring <jan.gehring@gmail.com>
Architecture: i386
Version: 0.44.0.93-1
Depends: perl, perl-modules, libnet-ssh2-perl, libexpect-perl, libdbi-perl, libwww-perl, liblwp-protocol-https-perl, libxml-simple-perl, libdigest-hmac-perl, libyaml-perl, libstring-escape-perl, libjson-xs-perl, liblist-moreutils-perl
Filename: pool/wheezy/rex/rex_0.44.0.93-1_i386.deb
Size: 291366
MD5sum: cff6d61c575a72e951c504c7fdabf1b2
SHA1: f749ca95ce6e0301a15fdbedcf210367b8692f8e
SHA256: 56b73041463dbcb6348fb64002706d68f9fe487f29ab3dbe9d6b6976fd7abbc0
SHA512: 25c16ad4a43d6412ff7d2adc45491000ebc3a58a6236f49f1115f73a47dfcc9a9bdd97c1a4d03f3f683cc0f55c97a17b0eda0b50404019748990f70aef1d9ed9
Description: Rex is a tool to ease the execution of commands on multiple remote servers.
 Rex is a tool to ease the execution of commands on multiple remote
 servers. You can define small tasks, chain tasks to batches, link
 them with servers or server groups, and execute them easily in
 your terminal.
Homepage: http://rexify.org/





Architectures: i386 amd64
Codename: wheezy
Components: rex
Date: Sun, 16 Feb 2014 09:48:14 UTC
Description: Rex Repository
Label: Rex
Origin: Rex
Suite: wheezy
MD5Sum:
 d41d8cd98f00b204e9800998ecf8427e                0 Release
 e7ff74a1fd28ff94abd2ed21996d7534            10896 rex/binary-amd64/Packages
 aeab4f82f28f62fbb24b58f7e06ccb47             2575 rex/binary-amd64/Packages.bz2
 d87ae784f4225efeeb92c5ea74139d03             2412 rex/binary-amd64/Packages.gz
 af210b1699678e0f17155c6565a057cd            10876 rex/binary-i386/Packages
 79ef536fec59fc8d61424dc497ec5179             2582 rex/binary-i386/Packages.bz2
 bbffdc3f371289ff1ff3aff8abb8d785             2416 rex/binary-i386/Packages.gz
SHA1:
 da39a3ee5e6b4b0d3255bfef95601890afd80709                0 Release
 3802b405e70f639b20f2e9efa76bfc0c2a09b749            10896 rex/binary-amd64/Packages
 5816983f478309af7ffbb9236864fbd9757eed0f             2575 rex/binary-amd64/Packages.bz2
 637418afbdaaaa67ed37907c9766346fd4766a79             2412 rex/binary-amd64/Packages.gz
 d7843006dae61ac2821e1941e2260f495e6798cd            10876 rex/binary-i386/Packages
 aba88405d603ee98b1abd42d0239d70016279073             2582 rex/binary-i386/Packages.bz2
 7b791125e6a28288ccc988b7e51ebefcea3b0db8             2416 rex/binary-i386/Packages.gz

<Repository debian-wheezy-rex>
  url    = http://nightly.rex.linux-files.org/debian/
  local  = debian-wheezy-rex/debian
  type   = Apt
  arch   = i386, amd64
  dist   = wheezy
  flavor = main, contrib, non-free
</Repository>
