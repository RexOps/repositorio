#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Yum::File;

use Mojo::Base 'Mojolicious::Controller';
use File::Spec;
use File::Path;

sub serve {
  my ($self) = @_;

  my $file = $self->req->url;
  $self->app->log->debug("Serving: $file");

#  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  my $repo_dir = File::Spec->rel2abs( $self->config->{RepositoryRoot} );

  $self->app->log->debug("Path: $repo_dir");

  my $serve_dir = File::Spec->catdir($repo_dir, $file);

  if( -d $serve_dir ) {
    my @entries;
    opendir(my $dh, $serve_dir) or die($!);
    while(my $entry = readdir($dh)) {
      next if($entry =~ m/^\./);
      push @entries, {
        name => $entry,
        file => (-f File::Spec->catfile($serve_dir, $entry)),
      };
    }
    closedir($dh);

    @entries = sort { "$a->{file}-$a->{name}" cmp "$b->{file}-$b->{name}" } @entries;

    $self->stash(path => $file);
    $self->stash(entries => \@entries);

    $self->render("file/serve");
  }
  else {
    $self->app->log->debug("File-Download: $serve_dir");
    return $self->render_file(filepath => $serve_dir);
  }
}

sub index {
  my ($self) = @_;

  my $repo_dir = File::Spec->rel2abs( $self->config->{RepositoryRoot} );

  # get tags
  opendir(my $dh, $repo_dir) or die($!);
  my @tags;
  while(my $entry = readdir($dh)) {
    next if($entry =~ m/^\./);
    if(-d File::Spec->catdir($repo_dir, $entry, $self->repo->{name})) {
      push @tags, $entry;
    }
  }
  closedir($dh);

  $self->stash("path", "/");
  $self->stash("tags", \@tags);
  $self->stash(repo_name => $self->repo->{name});

  $self->render("file/index");
}

1;
