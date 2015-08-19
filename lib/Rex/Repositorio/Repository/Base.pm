#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Base;

use Moose;
use Try::Tiny;
use common::sense;
use Carp;
use English;
use LWP::UserAgent;
use XML::LibXML;
use XML::Simple;
use Params::Validate qw(:all);
use IO::All;
use File::Path;
use File::Basename qw'dirname';
use File::Spec;
use File::Copy;
use Digest::SHA;
use Digest::MD5;
use JSON::XS;
use List::MoreUtils 'firstidx';

# VERSION

has app  => ( is => 'ro' );
has repo => ( is => 'ro' );

sub ua {
  my ($self) = @_;

  my %option;
  if ( exists $self->repo->{key} && exists $self->repo->{cert} ) {

    # we need ssl client cert authentication
    $option{ssl_opts} = {
      SSL_cert_file => $self->repo->{cert},
      SSL_key_file  => $self->repo->{key},
      SSL_ca_file   => $self->repo->{ca},
    };
  }

  return $self->app->ua(%option);
}

sub download_gzip {
  my ( $self, $url ) = @_;

  my $content = $self->download($url);

  require Compress::Zlib;

  my $t1 = time();
  my $un_content = Compress::Zlib::memGunzip($content);
  my $tdiff = time() - $t1;
  $self->app->logger->debug("Uncompressing: $url took: ${tdiff} seconds");
  if ( !$un_content ) {
    $self->app->logger->log_and_croak('error', message => 'Error uncompressing data.');
  }

  return $un_content;
}

sub gunzip {
  my ( $self, $data ) = @_;
  require Compress::Zlib;

  return Compress::Zlib::memGunzip($data);
}

sub download {
  my ( $self, $url ) = @_;

  my $retry_count = 0;
  my $max_retries = $self->app->config->{DownloadRetryCount} // 3;
  my $success;
  my $content;

  while (!$success && $retry_count <= $max_retries ) {
    my $t1 = time();
    my $resp = $self->ua->get($url);
    my $tdiff = time() - $t1;
    $self->app->logger->debug("Download: ${url} took: ${tdiff} seconds");

    if ( !$resp->is_success ) {
      $self->app->logger->error("Download: ${url} failed with status: " . $resp->status_line);
      $retry_count++;
      if ($retry_count <= $max_retries) {
        $self->app->logger->error("Download: ${url} retrying");
      }
      else {
        $self->app->logger->log_and_croak(level => 'error', message=> "download: ${url} failed and exhausted all retries.");
      }
    }
    else {
      $success = 1;
      $content = $resp->content;
    }
  }

  return $content;
}

sub get_xml {
  my ( $self, $xml ) = @_;
  return XML::LibXML->load_xml( string => $xml );
}

sub decode_xml {
  my ( $self, $xml ) = @_;
  return XMLin( $xml, ForceArray => 1 );
}

sub download_package {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      name => {
        type => SCALAR
      },
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF,
        optional => 1,
      },
      update_file => {
        type     => BOOLEAN,
        optional => 1,
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      },
    }
  );

  my $package_file;
  if ($self->app->config->{TagStyle} eq 'TopDir') {
    $package_file = File::Spec->catfile(
      $self->app->config->{RepositoryRoot}, 'head', $option{dest});
  }
  elsif ($self->app->config->{TagStyle} eq 'BottomDir') {
    # tag is inserted by caller
    $package_file = File::Spec->catfile(
      $self->app->config->{RepositoryRoot}, $option{dest});
  }
  else {
    $self->app->logger->log_and_croak(level => 'error', message => 'Unknown TagStyle: '.$self->app->config->{TagStyle})
  }

  $self->_download_binary_file(
    dest        => $package_file,
    url         => $option{url},
    cb          => $option{cb},
    force       => $option{force},
    update_file => $option{update_file},
  );
}

sub download_metadata {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF,
        optional => 1,
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      }
    }
  );

  my $metadata_file;
  if ($self->app->config->{TagStyle} eq 'TopDir') {
    $metadata_file = File::Spec->catdir(
      $self->app->config->{RepositoryRoot}, 'head', $option{dest});
  }
  elsif ($self->app->config->{TagStyle} eq 'BottomDir') {
    # tag is inserted by caller
    $metadata_file = File::Spec->catfile(
      $self->app->config->{RepositoryRoot}, $option{dest});
  }
  else {
    $self->app->logger->log_and_croak('Unknown TagStyle: '.$self->app->config->{TagStyle})
  }

  $self->_download_binary_file(
    dest  => $metadata_file,
    url   => $option{url},
    cb    => $option{cb},
    force => $option{force},
  );
}

sub _download_binary_file {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF | UNDEF,
        optional => 1,
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      },
      update_file => {
        type     => BOOLEAN,
        optional => 1,
      },
    }
  );

  $self->app->logger->debug("_download_binary_file: $option{url} -> $option{dest}");

  mkpath( dirname( $option{dest} ) ) if ( !-d dirname $option{dest} );

  if ( exists $option{cb}
    && ref $option{cb} eq "CODE"
    && $option{update_file}
    && -f $option{dest} )
  {
    eval {
      $option{cb}->( $option{dest} );
      1;
    } or do {

      # if callback is failing, we need to download the file once again.
      # so just set force to true
      $self->app->logger->debug(
        "_download_binary_file: $option{dest} Setting option force -> 1: update_file is enabled and callback failed."
      );
      $option{force} = 1;
    };
  }

  if ( -f $option{dest} && !$option{force} ) {
    $self->app->logger->debug("_download_binary_file: Skipping $option{dest}. File already exists and is the correct checksum");
    return;
  }

  if ( !-w dirname( $option{dest} ) ) {
    $self->app->logger->log_and_croak( level => 'error', message => "_download_binary_file: Can't write to " . dirname( $option{dest} ) );
  }

  if ( -f $option{dest} && $option{force} ) {
    $self->app->logger->debug("_download_binary_file: $option{dest} force enabled, unlinking");
    unlink $option{dest};
  }

  my $retry_count = 0;
  my $max_retries = $self->app->config->{DownloadRetryCount} // 3;
  my $success;

  while (!$success && $retry_count <= $max_retries ) {
    my $t1 = time();
    open my $fh, '>', $option{dest};
    binmode $fh;
    my $resp = $self->ua->get(
      $option{url},
      ':content_cb' => sub {
        my ( $data, $response, $protocol ) = @_;
        print $fh $data;
      }
    );
    close $fh;
    my $tdiff = time() - $t1;
    $self->app->logger->debug("_download_binary_file: $option{url} took: ${tdiff} seconds");

    if ( !$resp->is_success ) {
      unlink $option{dest};
      $self->app->logger->error("_download_binary_file: $option{url} failed with status: " . $resp->status_line);
      $retry_count++;
      if ($retry_count <= $max_retries) {
        $self->app->logger->error("_download_binary_file: $option{url} retrying");
      }
      else {
        $self->app->logger->log_and_croak(level => 'error', message=> "_download_binary_file: $option{url} failed and exhausted all retries.");
      }
    }
    else {
      $success = 1;
      $self->app->logger->notice("Downloaded new file: $option{url}");
    }
  }
  $option{cb}->( $option{dest} )
    if ( exists $option{cb} && ref $option{cb} eq "CODE" );
}

sub add_file_to_repo {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      source => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      }
    }
  );

  if ( !-f $option{source} ) {
    $self->app->logger->log_and_croak(level => 'error', message => "add_file_to_repo: File $option{source} not found.");
  }

  $self->app->logger->debug("add_file_to_repo: Copy $option{source} -> $option{dest}");
  my $ret = copy $option{source}, $option{dest};
  if ( !$ret ) {
    $self->app->logger->log_and_croak(level => 'error', message => "add_file_to_repo: Error copying file $option{source} to $option{dest}");
  }
}

sub remove_file_from_repo {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      }
    }
  );

  if ( !-f $option{file} ) {
    $self->app->logger->error("Fild $option{file} not found.");
    confess "Fild $option{file} not found.";
  }

  $self->app->logger->debug("Deleting $option{file}.");
  my $ret = unlink $option{file};
  if ( !$ret ) {
    $self->app->logger->error("Error deleting file $option{file}");
    confess "Error deleting file $option{file}";
  }
}

sub _checksum_md5 {
  my ( $self, $file, $wanted_checksum ) = @_;
  my $md5 = Digest::MD5->new;
  open my $fh, "<", $file;
  binmode $fh;
  $md5->addfile($fh);

  my $file_checksum = $md5->hexdigest;

  close $fh;

  $self->app->logger->debug("_checksum_md5: file: ${file} wanted_checksum: ${wanted_checksum} == ${file_checksum}");

  if ( $wanted_checksum ne $file_checksum ) {
    $self->app->logger->log_and_croak(level => 'error', message => "_checksum_md5: Checksum for ${file} wrong.");
  }
}
sub _checksum_size {
  my ( $self, $file, $wanted_size ) = @_;

  my @stats = stat($file);
  my $file_size = $stats[7];

  $self->app->logger->debug("_checksum_size: file: ${file} wanted_size: ${wanted_size} == ${file_size}");

  if ( $wanted_size ne $file_size ) {
    $self->app->logger->log_and_croak(level => 'error', message => "_checksum_size: File size for ${file} wrong.");
  }
}
sub _checksum_sha {
  my ($self, $c_type, $file, $wanted_checksum) = @_;

  my $sha = Digest::SHA->new($c_type);
  $sha->addfile($file);
  my $file_checksum = $sha->hexdigest;

  $self->app->logger->debug("_checksum: file: ${file} wanted_checksum: ${wanted_checksum} == ${file_checksum}");

  if ( $wanted_checksum ne $file_checksum ) {
    $self->app->logger->log_and_croak(level => 'error', message => "_checksum_sha: Checksum for ${file} wrong.");
  }
}

sub _checksum {
  my ( $self, $file, $type, $wanted_checksum ) = @_;

  my $c_type = 1;
  if ( $type eq "sha256" ) {
    $c_type = "256";
    return $self->_checksum_sha( $c_type, $file, $wanted_checksum );
  }
  elsif ( $type eq "md5" ) {
    return $self->_checksum_md5( $file, $wanted_checksum );
  }
  elsif ( $type eq 'size' ) {
    return $self->_checksum_size( $file, $wanted_checksum );
  }
  else {
    return $self->_checksum_sha( $c_type, $file, $wanted_checksum );
  }
}

sub verify_options {
  my ($self) = @_;

  if ( !exists $self->app->config->{RepositoryRoot}
    || !$self->app->config->{RepositoryRoot} )
  {
    confess "No repository root (RepositoryRoot) given in configuration file.";
  }
}

sub read_password {
  my ( $self, $msg ) = @_;
  $msg ||= "Password: ";

  print $msg;
  ReadMode "noecho";
  my $password = <STDIN>;
  chomp $password;
  ReadMode 0;
  print "\n";
  return $password;
}

sub get_errata {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      package => {
        type => SCALAR
      },
      version => {
        type => SCALAR
      },
      arch => {
        type => SCALAR
      },
    }
  );

  my $errata_dir =
    $self->app->get_errata_dir( repo => $self->repo->{name}, tag => "head" );

  if (
    !-f File::Spec->catfile(
      $errata_dir, $option{arch},
      substr( $option{package}, 0, 1 ), $option{package},
      "errata.json"
    )
    )
  {
    return {};
  }

  my $ref = decode_json(
    IO::All->new(
      File::Spec->catfile(
        $errata_dir, $option{arch},
        substr( $option{package}, 0, 1 ), $option{package},
        "errata.json"
      )
    )->slurp
  );

  my $package = $option{package};
  my $arch    = $option{arch};
  my $version = $option{version};

  my $pkg      = $ref;
  my @versions = keys %{$pkg};

  @versions = sort { $a cmp $b } @versions;

  my $idx = firstidx { ( $_ cmp $version ) == 1 } @versions;
  if ( $idx == -1 ) {

    # no updates found
    return {};
  }

  $idx = 0 if ( $idx <= 0 );

  my @update_versions = @versions[ $idx .. $#versions ];
  my $ret;
  for my $uv (@update_versions) {
    $ret->{$uv} = $pkg->{$uv};
  }

  return $ret;
}

sub update_errata {
  my $self = shift;

  my $errata_type = $self->repo->{errata};
  $self->app->logger->debug("Updating errata of type: $errata_type");

  my $data = $self->download("http://errata.repositor.io/$errata_type.tar.gz");
  # TODO: use File::Temp
  my $file = File::Spec->catfile(File::Spec->tmpdir(),"$errata_type.tar.gz");
  open( my $fh, '>', $file ) or confess($!);
  binmode $fh;
  print $fh $data;
  close($fh);

  my $errata_dir =
    $self->app->get_errata_dir( repo => $self->repo->{name}, tag => "head" );

  mkpath $errata_dir;

  system "cd $errata_dir ; tar xzf $file"; #TODO: replace with perl

  if ( $? != 0 ) {
    confess "Error extracting errata database.";
  }

  unlink $file;

  $self->app->logger->debug("Updating errata of type: $errata_type (done)");
}

1;
