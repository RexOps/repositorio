#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:
#
use strict;

package Rex::Repositorio::Server::Yum::File;

use Mojo::Base 'Mojolicious::Controller';
use File::Spec;
use File::Path;
use File::Basename qw'dirname';
use Mojo::UserAgent;

# VERSION

sub serve {
  my ($self) = @_;

  my $file = $self->req->url;
  $self->app->log->debug("Serving: $file");

  #  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $repo_dir = File::Spec->rel2abs( $self->config->{RepositoryRoot} );

  $self->app->log->debug("Path: $repo_dir");

  my $serve_dir = File::Spec->catdir( $repo_dir, $file );
  $self->app->log->debug("Serving URL: $serve_dir");

  my $orig_url   = $file;
  my $local_part = $self->repo->{local};
  my $repo_url   = $self->repo->{url};

  if ($repo_url) {
    $repo_url =~ s/\/$//;

    $orig_url =~ s/^\/([^\/]+)\/\Q$local_part\E//;

    if ( $repo_url !~ m/\/$/ ) {
      $repo_url .= "/";
    }

    $orig_url = $repo_url . $orig_url;

    $self->app->log->debug("Orig-URL: $orig_url");
  }

  my $do_proxy = lc( $self->repo->{proxy} || "false" );

  if ( -d $serve_dir ) {
    my @entries;
    opendir( my $dh, $serve_dir ) or die($!);
    while ( my $entry = readdir($dh) ) {
      next if ( $entry =~ m/^\./ );
      push @entries,
        {
        name => $entry,
        file => ( -f File::Spec->catfile( $serve_dir, $entry ) ),
        };
    }
    closedir($dh);

    @entries =
      sort { "$a->{file}-$a->{name}" cmp "$b->{file}-$b->{name}" } @entries;

    $self->stash( path    => $file );
    $self->stash( entries => \@entries );

    $self->render("file/serve");
  }
  elsif ( -f $serve_dir ) {
    $self->app->log->debug("File-Download: $serve_dir");

    if ( -f "$serve_dir.etag" && ( $do_proxy eq "true" || $do_proxy eq "on" ) )
    {

      # there is an etag file, so the file was downloaded via proxy
      # check upstream if file is out-of-date
      my ($etag) = eval { local ( @ARGV, $/ ) = ("$serve_dir.etag"); <>; };
      $self->app->log->debug(
        "Making ETag request to upstream ($orig_url): ETag: $etag.");
      my $tx = $self->ua->head( $orig_url,
        { Accept => '*/*', 'If-None-Match' => $etag } );
      if ( $tx->success ) {
        my $upstream = $tx->res->headers->header('ETag');
        $upstream =~ s/"//g;
        if ( $upstream ne $etag ) {
          $self->app->log->debug(
            "Upstream ETag and local ETag does not match: $upstream != $etag");
          return $self->_proxy_url( $orig_url, $serve_dir );
        }
        else {
          $self->app->log->debug(
            "Upstream ETag and local ETag are the same: $upstream == $etag");
        }
      }
    }

    return $self->render_file( filepath => $serve_dir );
  }
  elsif ( $do_proxy eq "true" || $do_proxy eq "on" ) {
    $self->app->log->debug("Need to get file from upstream: $orig_url");
    return $self->_proxy_url( $orig_url, $serve_dir );
  }
  else {
    $self->render( text => "Not found", status => 404 );
  }
}

sub index {
  my ($self) = @_;

  my $repo_dir = File::Spec->rel2abs( $self->config->{RepositoryRoot} );

  # get tags
  opendir( my $dh, $repo_dir ) or die($!);
  my @tags;
  while ( my $entry = readdir($dh) ) {
    next if ( $entry =~ m/^\./ );
    if ( -d File::Spec->catdir( $repo_dir, $entry, $self->repo->{name} ) ) {
      push @tags, $entry;
    }
  }
  closedir($dh);

  $self->stash( "path", "/" );
  $self->stash( "tags", \@tags );
  $self->stash( repo_name => $self->repo->{name} );

  $self->render("file/index");
}

sub _proxy_url {
  my ( $self, $orig_url, $serve_dir ) = @_;

  return $self->proxy_to(
    $orig_url,
    sub {
      my ( $c, $tx ) = @_;
      $c->app->log->debug("Got data from upstream ($orig_url)...");
      mkpath( dirname($serve_dir) );
      open my $fh, '>', $serve_dir or die($!);
      binmode $fh;
      print $fh $tx->res->body;
      close $fh;

      my $etag = $tx->res->headers->header('ETag');
      $etag =~ s/"//g;
      open my $fh_e, '>', "$serve_dir.etag" or die($!);
      print $fh_e $etag;
      close $fh_e;
    }
  );
}

1;
