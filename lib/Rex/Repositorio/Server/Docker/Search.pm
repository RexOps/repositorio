#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker::Search;

use Mojo::Base 'Mojolicious::Controller';
use File::Spec;
require IO::All;
use JSON::XS;
use Data::Dumper;

sub search {
  my ($self) = @_;

  my $repo_dir = File::Spec->catdir($self->app->get_repo_dir( repo => $self->repo->{name} ), "repository");

  my @json_files;
  my @dirs = ($repo_dir);
  for my $dir (@dirs) {
    opendir(my $dh, $dir);
    while(my $entry = readdir($dh)) {
      next if($entry =~ m/^\./);
      if(-d File::Spec->catdir($dir, $entry)) {
        push @dirs, File::Spec->catdir($dir, $entry);
      }
      if(-f File::Spec->catfile($dir, $entry, "repo.json")) {
        push @json_files, File::Spec->catfile($dir, $entry, "repo.json");
      }
    }
    closedir($dh);
  }

  my $search = $self->param("q");

  my @search_result = 
    map {
      my @_t = split(/\//, $_);
      $_ = {
        description => '',
        name        => "$_t[-3]/$_t[-2]",
      }
    }
    grep {
      m/\Q$search\E/
    } @json_files;
  
  my $ret = {
    num_results => 1,
    query       => $search,
    results     => \@search_result,
  };

  $self->render( json => $ret );
}

1;
