#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio;

use Moo;
use English;
use common::sense;
use Carp;
use LWP::UserAgent;
use Compress::Zlib;
use Compress::Bzip2;
use XML::LibXML;
use XML::Simple;
use Params::Validate qw(:all);
use IO::All;
use File::Path;
use File::Basename qw'dirname';

our $VERSION = "0.0.1";

has config => ( is => 'ro' );
has logger => ( is => 'ro' );
has ua     => (
  is      => 'ro',
  default => sub {
    my $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    return $ua;
  }
);

sub run {
  my ( $self, %option ) = @_;

  $self->config->{RepositoryRoot} =~ s/\/$//;
  $self->parse_cli_option(%option);
}

sub parse_cli_option {
  my ( $self, %option ) = @_;

  if ( exists $option{help} ) {
    $self->_help();
    exit 0;
  }

  if ( exists $option{mirror} && exists $option{repo} ) {
    $self->mirror(
      repo            => $option{repo},
      update_metadata => $option{"update-metadata"},
      update_files    => $option{"update-files"},
    );
  }

  elsif ( exists $option{tag} && exists $option{repo} ) {
    $self->tag( tag => $option{tag}, repo => $option{repo} );
  }
}

sub mirror {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
      update_metadata => {
        type     => BOOLEAN,
        optional => 1,
      },
      update_files => {
        type     => BOOLEAN,
        optional => 1,
      },
    }
  );

  my @repositories = ( $option{repo} );
  if ( $option{repo} eq "all" ) {
    @repositories = keys %{ $self->config->{Repository} };
  }

  for my $repo (@repositories) {
    my $type     = $self->config->{Repository}->{$repo}->{type};
    my $repo_mod = "Rex::Repositorio::Repository::$type";
    eval "use $repo_mod;";
    if ($EVAL_ERROR) {
      confess "Error loading repository type: $type. ($EVAL_ERROR)";
    }

    my $repo_o = $repo_mod->new(
      app  => $self,
      repo => {
        name => $repo,
        %{ $self->config->{Repository}->{$repo} },
      }
    );
    $repo_o->mirror(
      update_metadata => $option{update_metadata},
      update_files    => $option{update_files}
    );
  }
}

sub tag {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
      tag => {
        type => SCALAR
      },
    }
  );

  my $repo_config = $self->config->{Repository}->{ $option{repo} };
  my $root_dir    = $self->config->{RepositoryRoot};
  $repo_config->{local} =~ s/\/$//;

  my @dirs    = ("$root_dir/head/$repo_config->{local}");
  my $tag_dir = "$root_dir/$option{tag}/$repo_config->{local}";

  mkpath $tag_dir;

  for my $dir (@dirs) {
    opendir my $dh, $dir;
    while ( my $entry = readdir $dh ) {
      next if ( $entry eq "." || $entry eq ".." );
      my $rel_entry = "$dir/$entry";
      $rel_entry =~ s/$root_dir\/head\/$repo_config->{local}\///;

      if ( -d "$dir/$entry" ) {
        push @dirs, "$dir/$entry";
        $self->logger->debug("Creating directory: $tag_dir/$rel_entry.");
        mkdir "$tag_dir/$rel_entry";
        next;
      }

      $self->logger->debug(
        "Linking (hard): $dir/$entry -> $tag_dir/$rel_entry");
      link "$dir/$entry", "$tag_dir/$rel_entry";
    }
    closedir $dh;
  }
}

sub download_gzip {
  my ( $self, $url ) = @_;

  my $content = $self->download($url);

  $self->logger->debug("Starting uncompressing of: $url");
  my $un_content = Compress::Zlib::memGunzip($content);
  $self->logger->debug("Finished uncompressing of: $url");
  if ( !$un_content ) {
    $self->logger->error("Error uncompressing data.");
    confess "Error uncompressing data.";
  }

  return $un_content;
}

sub download_bzip2 {
  my ( $self, $url ) = @_;

  my $content = $self->download($url);

  $self->logger->debug("Starting uncompressing of: $url");
  my $un_content = Compress::Bzip2::memBunzip($content);
  $self->logger->debug("Finished uncompressing of: $url");
  if ( !$un_content ) {
    $self->logger->error("Error uncompressing data.");
    confess "Error uncompressing data.";
  }

  return $un_content;
}

sub download {
  my ( $self, $url ) = @_;

  $self->logger->debug("Starting download of: $url");
  my $resp = $self->ua->get($url);
  $self->logger->debug("Finished download of: $url");

  if ( !$resp->is_success ) {
    $self->logger->error("Can't download $url.");
    $self->logger->error( "Status: " . $resp->status_line );
    confess "Error downloading $url.";
  }

  return $resp->content;
}

sub get_xml {
  my ( $self, $xml ) = @_;
  return XML::LibXML->load_xml(string => $xml);
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
        type => CODEREF
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      }
    }
  );

  my $package_file = $self->config->{RepositoryRoot} . "/head/" . $option{dest};
  $self->_download_binary_file(
    dest  => $package_file,
    url   => $option{url},
    cb    => $option{cb},
    force => $option{force},
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

  my $metadata_file =
    $self->config->{RepositoryRoot} . "/head/" . $option{dest};
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
        type => BOOLEAN
      }
    }
  );

  $self->logger->debug("Downloading: $option{url} -> $option{dest}");

  mkpath( dirname( $option{dest} ) ) if ( !-d dirname $option{dest} );

  if ( -f $option{dest} && !$option{force} ) {
    $self->logger->debug("Skipping $option{url}. File aready exists.");
    return;
  }

  if ( !-w dirname( $option{dest} ) ) {
    $self->logger->error( "Can't write to " . dirname( $option{dest} ) );
    confess "Can't write to " . dirname( $option{dest} );
  }

  if ( -f $option{dest} && $option{force} ) {
    unlink $option{dest};
  }

  open my $fh, ">", $option{dest};
  binmode $fh;
  my $resp = $self->ua->get(
    $option{url},
    ':content_cb' => sub {
      my ( $data, $response, $protocol ) = @_;
      print $fh $data;
    }
  );
  close $fh;

  if ( !$resp->is_success ) {
    $self->logger->error("Can't download $option{url}.");
    $self->logger->error( "Status: " . $resp->status_line );
    confess "Error downloading $option{url}.";
  }

  $option{cb}->( $option{dest} ) if ( exists $option{cb} && $option{cb} );
}

sub _help {
  my ($self) = @_;

  print "repo-mirror: $VERSION\n";
  print "-" x 80;
  print "\n";
  print "--mirror            mirror a configured repository (needs --repo)\n";
  print "--tag=tagname       tag a repository (needs --repo)\n";
  print "--repo=reponame     the name of the repository to use.\n";
  print "--update-metadata   update the metadata of a repository\n";
  print
    "--update-files      download files even if they are already downloaded\n";
  print "--help              display this help message\n";

}

1;
