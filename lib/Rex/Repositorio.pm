#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio;

use Moose;
use English;
use common::sense;
use Carp;
use LWP::UserAgent;
use XML::LibXML;
use XML::Simple;
use Params::Validate qw(:all);
use IO::All;
use File::Path;
use File::Basename qw'dirname';
use File::Spec;
use File::Copy;
use Rex::Repositorio::Repository_Factory;
use JSON::XS;
use Data::Dumper;
use Term::ProgressBar;
use Term::ANSIColor;

# VERSION

has config => ( is => 'ro' );
has logger => ( is => 'ro' );

sub ua {
  my ( $self, %option ) = @_;
  my $ua = LWP::UserAgent->new;
  $ua->env_proxy;

  if ( $self->config->{DownloadTimeout} ) {
    $self->logger->debug(
      "Setting download timeout to: " . $self->config->{DownloadTimeout} );
    $ua->timeout( $self->config->{DownloadTimeout} );
  }

  if ( exists $option{ssl_opts} ) {
    for my $key ( keys %{ $option{ssl_opts} } ) {
      $ua->ssl_opts( $key, $option{ssl_opts}->{$key} );
    }
  }

  return $ua;
}

sub run {
  my ( $self, %option ) = @_;

  # this config checking/munging stuff should probably be in the 'has config' definition?
  $self->config->{RepositoryRoot} =~ s/\/$//;
  $self->logger->logcroak(qq/"all" is a reserved word and cannot be used as a repo name\n/)
    if grep { $_ eq 'all' } keys %{ $self->config->{Repository} };
  $self->config->{TagStyle} ||= 'TopDir';
  $self->logger->logcroak(
    sprintf "Unknown TagStyle %s, must be TopDir or BottomDir\n", $self->config->{TagStyle} )
    unless $self->config->{TagStyle} =~ m/^(?:Top|Bottom)Dir$/;

  $self->parse_cli_option(%option);
}

sub parse_cli_option {
  my ( $self, %option ) = @_;

  if ( exists $option{help} ) {
    $self->_help();
    exit 0;
  }

  if ( exists $option{repo} ) {
    $self->logger->logcroak(sprintf("Unknown repo: %s\n", $option{repo}))
      unless $option{repo} eq 'all'
        or $self->config->{Repository}->{ $option{repo} };
  }

  if ( exists $option{mirror} && exists $option{repo} ) {
    $self->print_info(
      "Going to mirror " . $option{repo} . ". This may take a while." );
    print "\n";

    my $update_files = 1;

   # so it is possible to only update metadata. (for example: for proxy support)
    if ( exists $option{"no-update-files"} && $option{"no-update-files"} ) {
      $update_files = 0;
    }

    $self->mirror(
      repo            => $option{repo},
      size_only       => $option{'size-only'},
      update_metadata => ( $option{"update-metadata"} || 0 ),
      update_files    => $update_files,
      force           => ( $option{"force-download"} || 0 ),
    );

    print "\n";
    print "\n";
    $self->print_info( "Finished downloading of files for " . $option{repo} );
    print "\n";
  }

  elsif ( exists $option{tag} && exists $option{repo} ) {
    $self->tag(
      tag => $option{tag},
      clonetag => $option{clonetag} || 'head',
      repo => $option{repo},
      force => $option{force} || 0,
    );
  }

  elsif ( exists $option{repo} && exists $option{"update-errata"} ) {
    $self->update_errata( repo => $option{repo} );
  }

  elsif ( exists $option{errata}
    && exists $option{package}
    && exists $option{arch}
    && exists $option{repo}
    && exists $option{version} )
  {
    $self->print_errata(
      package => $option{package},
      arch    => $option{arch},
      version => $option{version},
      repo    => $option{repo},
    );
  }

  elsif ( exists $option{server} && exists $option{repo} ) {
    $self->server( repo => $option{repo} );
  }

  elsif ( exists $option{list} ) {
    $self->list();
  }

  elsif ( exists $option{init} && exists $option{repo} ) {
    $self->init( repo => $option{repo} );
  }

  elsif ( exists $option{"add-file"} && exists $option{repo} ) {
    $self->add_file( file => $option{"add-file"}, repo => $option{repo} );
  }

  elsif ( exists $option{"remove-file"} && exists $option{repo} ) {
    $self->remove_file( file => $option{"remove-file"}, repo => $option{repo} );
  }

  else {
    $self->_help();
    exit 0;
  }
}

sub server {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
    }
  );

  require Mojolicious::Commands;

  # pass config to mojo app
  $ENV{'REPO_CONFIG'} = encode_json( $self->config );
  $ENV{'REPO_NAME'}   = $option{repo};
  $ENV{'MOJO_MAX_MESSAGE_SIZE'} = 1024 * 1024 * 1024 * 1024; # set max_message_size astronomically high / TODO: make it configurable
  my $server_type = $self->config->{Repository}->{ $option{repo} }->{type};
  if ( $server_type eq "Apt"
    || $server_type eq "OpenSuSE"
    || $server_type eq "Plain" )
  {
    $server_type = "Yum";
  }
  Mojolicious::Commands->start_app("Rex::Repositorio::Server::$server_type");
}

sub add_file {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      },
      repo => {
        type => SCALAR
      }
    }
  );

  my $repo   = $self->config->{Repository}->{ $option{repo} };
  my $type   = $repo->{type};
  my $repo_o = Rex::Repositorio::Repository_Factory->create(
    type    => $type,
    options => {
      app  => $self,
      repo => {
        name => $option{repo},
        %{$repo},
      }
    }
  );

  $repo_o->add_file( file => $option{file} );
}

sub remove_file {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      },
      repo => {
        type => SCALAR
      }
    }
  );

  my $repo   = $self->config->{Repository}->{ $option{repo} };
  my $type   = $repo->{type};
  my $repo_o = Rex::Repositorio::Repository_Factory->create(
    type    => $type,
    options => {
      app  => $self,
      repo => {
        name => $option{repo},
        %{$repo},
      }
    }
  );

  $repo_o->remove_file( file => $option{file} );
}

sub list {
  my $self  = shift;
  my @repos = keys %{ $self->config->{Repository} };

  $self->_print(@repos);
}

sub update_errata {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
    }
  );

  my $repo   = $self->config->{Repository}->{ $option{repo} };
  my $type   = $repo->{type};
  my $repo_o = Rex::Repositorio::Repository_Factory->create(
    type    => $type,
    options => {
      app  => $self,
      repo => {
        name => $option{repo},
        %{$repo},
      }
    }
  );

  $repo_o->update_errata();
}

sub print_errata {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
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

  my $repo   = $self->config->{Repository}->{ $option{repo} };
  my $type   = $repo->{type};
  my $repo_o = Rex::Repositorio::Repository_Factory->create(
    type    => $type,
    options => {
      app  => $self,
      repo => {
        name => $option{repo},
        %{$repo},
      }
    }
  );

  my $errata = $repo_o->get_errata(
    arch    => $option{arch},
    package => $option{package},
    version => $option{version}
  );

  for my $pkg_version ( sort { $a cmp $b } keys %{$errata} ) {
    print "Name       : $errata->{$pkg_version}->[0]->{advisory_name}\n";
    print "Version    : $pkg_version\n";
    print "Synopsis   : $errata->{$pkg_version}->[0]->{synopsis}\n";
    print "References : $errata->{$pkg_version}->[0]->{references}\n";
    print "Type       : $errata->{$pkg_version}->[0]->{type}\n";
    print "\n";
  }
}

sub init {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      }
    }
  );

  my $repo = $self->config->{Repository}->{ $option{repo} };

  if ( !$repo ) {
    $self->logger->error("Repository $option{repo} not found.");
    confess "Repository $option{repo} not found.";
  }

  my $type   = $repo->{type};
  my $repo_o = Rex::Repositorio::Repository_Factory->create(
    type    => $type,
    options => {
      app  => $self,
      repo => {
        name => $option{repo},
        %{$repo},
      }
    }
  );

  $repo_o->verify_options;
  $repo_o->init;
}

sub mirror {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
      size_only => {
        type     => BOOLEAN,
        optional => 1,
      },
      update_metadata => {
        type     => BOOLEAN,
        optional => 1,
      },
      update_files => {
        type     => BOOLEAN,
        optional => 1,
      },
      force => {
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
    my $type = $self->config->{Repository}->{$repo}->{type};

    my $repo_o = Rex::Repositorio::Repository_Factory->create(
      type    => $type,
      options => {
        app  => $self,
        repo => {
          name => $repo,
          %{ $self->config->{Repository}->{$repo} },
        }
      }
    );

    $repo_o->mirror(
      size_only       => $option{size_only},
      update_metadata => $option{update_metadata},
      update_files    => $option{update_files},
      force           => $option{force},
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
      clonetag => {
        type => SCALAR
      },
      force => {
        type => BOOLEAN
      }
    }
  );

  my $repo_config = $self->config->{Repository}->{ $option{repo} };
  my $root_dir    = $self->config->{RepositoryRoot};
  $repo_config->{local} =~ s/\/$//;

  my (@dirs, $tag_dir);

  # should probably use get_repo_dir ?
  if ($self->config->{TagStyle} eq 'TopDir') {
    push @dirs, File::Spec->catdir($root_dir, $option{clonetag}, $repo_config->{local});
    $tag_dir = File::Spec->catdir($root_dir, $option{tag}, $repo_config->{local});
  }
  elsif ($self->config->{TagStyle} eq 'BottomDir') {
    push @dirs, File::Spec->catdir($root_dir, $repo_config->{local}, $option{clonetag});
    $tag_dir = File::Spec->catdir($root_dir, $repo_config->{local}, $option{tag});
  }
  else {
    # add other styles here
    $self->logger->logcroak('Shouldnt have gotten here');
  }

  $self->logger->logcroak("Unknown tag $option{clonetag} on repo $option{repo} ($dirs[0])\n")
    unless ( -d $dirs[0] );

  if ( -e $tag_dir ) {
    if( $option{force} ) {
      $self->logger->debug("Removing $tag_dir");
      rmtree $tag_dir; # should be remove_tree, but will use legacy to match mkdir
    }
    else {
      $self->logger->logcroak("Tag $option{tag} on repo $option{repo} already exists ($tag_dir), use --force\n");
    }
  }

  mkpath $tag_dir;

  for my $dir (@dirs) {
    opendir my $dh, $dir
        or $self->logger->logcroak("Failed to open $dir: $!\nNew tag is probably unusable\n");
    while ( my $entry = readdir $dh ) {
      next if ( $entry eq '.' || $entry eq '..' );
      my $rel_entry = File::Spec->catfile($dir, $entry);
      $rel_entry =~ s{^$dirs[0]/}{}; # TODO use File::Spec?

      my $srcfile = File::Spec->catfile($dir,$entry);
      my $dstfile = File::Spec->catfile($tag_dir,$rel_entry);
      $self->logger->debug("Tag Src: $srcfile, Dst: $dstfile");

      if ( -d $srcfile ) {
        push @dirs, $srcfile;
        $self->logger->debug("Creating directory: $dstfile");
        mkdir $dstfile;
        next;
      }

      $self->logger->debug(
        "Linking (hard): $srcfile -> $dstfile");
      link $srcfile, $dstfile;
    }
    closedir $dh;
  }
}

sub get_errata_dir {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      },
      tag => {
        type => SCALAR
      }
    }
  );

  if ($self->config->{TagStyle} eq 'TopDir') {
    return File::Spec->catdir(
      File::Spec->rel2abs( $self->config->{RepositoryRoot} ),
      $option{tag}, $option{repo}, 'errata' );
  }
  elsif ($self->config->{TagStyle} eq 'BottomDir') {
    return File::Spec->catdir(
      File::Spec->rel2abs( $self->config->{RepositoryRoot} ),
      $option{repo}, $option{tag}, 'errata' );
  }
  else {
    # add other styles here
    $self->logger->logcroak('Shouldnt have gotten here');
  }

}

sub get_repo_dir {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      repo => {
        type => SCALAR
      }
    }
  );

  if ($self->config->{TagStyle} eq 'TopDir') {
    return File::Spec->catdir(
      File::Spec->rel2abs( $self->config->{RepositoryRoot} ),
      'head', $option{repo});
  }
  elsif ($self->config->{TagStyle} eq 'BottomDir') {
    return File::Spec->catdir(
      File::Spec->rel2abs( $self->config->{RepositoryRoot} ),
      $option{repo}, 'head');
  }
  else {
    # add other styles here
    $self->logger->logcroak('Shouldnt have gotten here');
  }

}

sub progress_bar {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      title => {
        type => SCALAR,
      },
      length => {
        type => SCALAR,
      }
    }
  );

  $self->print_info( $option{title} );
  print "\n";

  my $pr = Term::ProgressBar->new( { count => $option{length} } );
  return $pr;
}

sub print_info {
  my ( $self, $msg ) = @_;
  print color "bold green";
  print ">> ";
  print color "reset";

  my @parts = split( / /, $msg );
  my $current_line_len = 3;

  for my $part (@parts) {
    $current_line_len += length $part;
    if ( $current_line_len >= 80 ) {
      print "\n   ";
      $current_line_len = 3;
    }

    print "$part ";
  }

  print "\n";
}

sub _print {
  my $self  = shift;
  my @lines = @_;

  print "repositorio: $VERSION\n";
  print "-" x 80;
  print "\n";
  print "$_\n" for @lines;
}

sub _help {
  my ($self) = @_;

  $self->_print(
    "--mirror            mirror a configured repository (needs --repo, use \"all\" for all repos)",
    "--tag=tagname       tag a repository (needs --repo)",
    "--clonetag=tagname  clones a tag in a repository (needs --repo and new --tag)",
    "--repo=reponame     the name of the repository to use",
    "--update-metadata   update the metadata of a repository",
    "--update-files      download files even if they are already downloaded",
    "--force-download    force the download of already downloaded files",
    "--no-update-files   do not download packages",
    "--init              initialize an empty repository",
    "--add-file=file     add a file to a repository (needs --repo)",
    "--remove-file=file  remove a file from a repository (needs --repo)",
    "--list              list known repositories",
    "--server            start a server for file delivery. (not available for all repository types)",
    "--update-errata     updates the errata database for a repo (needs --repo)",
    "--errata            query errata for a package (needs --repo, --package, --version, --arch)",
    "  --package=pkg     for which package the errata should be queries",
    "  --version=ver     for which version of a package the errata should be queries",
    "  --arch=arch       for which architecture of a package the errata should be queries",
    "--help              display this help message",
  );

}

1;

__END__

# ABSTRACT: repositor.io is a tool to create and manage linux repositories.

=pod

=head1 repositor.io - Linux Repository Management

repositor.io is a tool to create and manage linux repositories.
You can mirror online repositories so that you don't need to download the
package every time you set up a new server. You can also secure your servers
behind a firewall and disable outgoing http traffic.

With repositor.io it is easy to create custom repositories for your own
packages. With the integration of a configuration management tool you can
create consistant installations of your server.

=head2 GETTING HELP

=over 4

=item * Web Site: L<http://repositor.io/>

=item * IRC: irc.freenode.net #rex (RexOps IRC Channel)

=item * Bug Tracker: L<https://github.com/RexOps/repositorio/issues>

=item * Twitter: L<http://twitter.com/RexOps>

=back

=head2 COMMAND LINE

=over 4

=item --mirror            mirror a configured repository (needs --repo, use "all" for all repos)

=item --tag=tagname       tag a repository (needs --repo)

=item --clonetag=tagname  clones a tag in a repository (needs --repo and new --tag)

=item --repo=reponame     the name of the repository to use

=item --update-metadata   update the metadata of a repository

=item --update-files      download files even if they are already downloaded

=item --init              initialize an empty repository

=item --add-file=file     add a file to a repository (needs --repo)

=item --remove-file=file  remove a file from a repository (needs --repo)

=item --list              list known repositories

=item --server            start a server for file delivery. (not available for all repository types)

=item --update-errata     updates the errata database for a repo (needs --repo)",

=item --errata            query errata for a package (needs --repo, --package, --version, --arch)",

=item --package=pkg       for which package the errata should be queries",

=item --version=ver       for which version of a package the errata should be queries",

=item --arch=arch         for which architecture of a package the errata should be queries",

=item --help              display this help message

=back

=head2 CONFIGURATION

To configure repositor.io create a configuration file
I</etc/rex/repositorio.conf>.
 RepositoryRoot = /srv/html/repo/

 TagStyle = TopDir

 # log4perl configuration file
 <Log4perl>
   config = /etc/rex/io/log4perl.conf
 </Log4perl>

 # create a mirror of the nightly rex repository
 # the files will be stored in
 # /srv/html/repo/head/rex-centos-6-x86-64/CentOS/6/rex/x86_64/
 <Repository rex-centos-6-x86-64>
   url   = http://nightly.rex.linux-files.org/CentOS/6/rex/x86_64/
   local = rex-centos-6-x86-64/CentOS/6/rex/x86_64/
   type  = Yum
 </Repository>

 # create a mirror of centos 6
 # and download the pxe boot files, too.
 <Repository centos-6-x86-64>
   url    = http://ftp.hosteurope.de/mirror/centos.org/6/os/x86_64/
   local  = centos-6-x86-64/CentOS/6/os/x86_64/
   type   = Yum
   images = true
 </Repository>

 # create a custom repository
 <Repository centos-6-x86-64-mixed>
   local = centos-6-x86-64-mixed/mixed/6/x86_64/
   type  = Yum
 </Repository>

 <Repository debian-wheezy-i386-main>
   url       = http://ftp.de.debian.org/debian/
   local     = debian-wheezy-amd64-main/debian
   type      = Apt
   arch      = i386
   dist      = wheezy
   component = main
 </Repository>

If you want to sign your custom repositories you have to configure the gpg key to use.
repositorio automatically exports the public key into the root of the repository, so it can be imported from the clients.
If you don't specify the gpg password repositorio will ask you for the password.

An example for YUM repositories:

 <Repository centos-6-x86-64-mixed>
   local = centos-6-x86-64-mixed/mixed/6/x86_64/
   type  = Yum
   <gpg>
     key      = DA95F273
     password = test
   </gpg>
 </Repository>

An example for APT repositories:

 <Repository debian-7-x86-64-mixed>
   local     = debian-7-x86-64-mixed/debian
   type      = Apt
   arch      = amd64
   dist      = wheezy
   component = mixed
   <gpg>
     key      = DA95F273
     password = test
   </gpg>
 </Repository>

An example log4perl.conf file:

 log4perl.rootLogger                    = DEBUG, FileAppndr1

 log4perl.appender.FileAppndr1          = Log::Log4perl::Appender::File
 log4perl.appender.FileAppndr1.filename = /var/log/repositorio.log
 log4perl.appender.FileAppndr1.layout   = Log::Log4perl::Layout::SimpleLayout
