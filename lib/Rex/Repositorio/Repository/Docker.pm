#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Docker;

use Moose;
use Try::Tiny;
use File::Basename qw'basename';
use Data::Dumper;
use Carp;
use Params::Validate qw(:all);
use File::Spec;
use File::Path;

extends "Rex::Repositorio::Repository::Base";

sub init {
  my $self = shift;

  my $repo_dir = $self->app->get_repo_dir( repo => $self->repo->{name} );
  mkpath "$repo_dir";
}

1;
