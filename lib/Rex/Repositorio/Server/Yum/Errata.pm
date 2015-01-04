#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Yum::Errata;

use Mojo::Base 'Mojolicious::Controller';
use File::Spec;
use File::Path;
use JSON::XS;
use List::MoreUtils 'firstidx';
use Data::Dumper;
require IO::All;

sub query {
  my ($self) = @_;

  my $errata_dir = File::Spec->catdir(File::Spec->rel2abs( $self->config->{RepositoryRoot} ), $self->param("tag"), $self->param("repo"), "errata");

  $self->app->log->debug("Looking for errata: $errata_dir");

  if(! -d $errata_dir) {
    return $self->render(json => {}, status => 404);
  }

  my $package = $self->param("package");
  my $arch    = $self->param("arch");
  my $version = $self->param("version");

  my $ref = decode_json(
    IO::All->new(
      File::Spec->catfile(
        $errata_dir, $arch,
        substr( $package, 0, 1 ), $package,
        "errata.json"
      )
    )->slurp
  );

  my $pkg = $ref;
  my @versions = keys %{ $pkg };

  @versions = sort { $a cmp $b } @versions;

  my $idx = firstidx { ($_ cmp $version) == 1 } @versions;
  if($idx == -1) {
    # no updates found
    return $self->render(json => {});
  }

  $idx = 0 if($idx <= 0);

  my @update_versions = @versions[$idx..$#versions];
  my $ret;
  for my $uv (@update_versions) {
    $ret->{$uv} = $pkg->{$uv};
  }

  $self->render(json => $ret);
}
