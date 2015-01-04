#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Yum;

use Mojo::Base 'Mojolicious';
use Data::Dumper;
use JSON::XS;
use File::Spec;
use Params::Validate qw(:all);
use File::Basename 'dirname';
use File::Spec::Functions 'catdir';

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->plugin("Rex::Repositorio::Server::Helper::Common");

  $self->app->log(
    Mojo::Log->new(
      level => 'debug',
    )
  );

  $self->plugin("Rex::Repositorio::Server::Helper::RenderFile");

  my $r = $self->routes;
  $r->get('/')->to('file#index');
  $r->get('/:tag')->to('file#index');
  $r->get('/:tag/:repo/errata')->to('errata#query');
  $r->get('/*')->to('file#serve');

  # Switch to installable home directory
  $self->home->parse( catdir( dirname(__FILE__), 'Yum' ) );

  # Switch to installable "public" directory
  $self->static->paths->[0] = $self->home->rel_dir('public');

  # Switch to installable "templates" directory
  $self->renderer->paths->[0] = $self->home->rel_dir('templates');
}

1;
