#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Server::Docker;

use Mojo::Base 'Mojolicious';
use Data::Dumper;
use JSON::XS;
use File::Spec;
use Params::Validate qw(:all);

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->plugin("RenderFile");

  $self->helper(
    config => sub {
      my $config = decode_json( $ENV{REPO_CONFIG} );
      return $config;
    },
  );

  $self->helper(
    repo => sub {
      my $self = shift;
      return {
        %{ $self->config->{Repository}->{ $ENV{REPO_NAME} } },
        name => $ENV{REPO_NAME}
      };
    },
  );

  $self->helper(
    get_repo_dir => sub {
      my $self   = shift;
      my %option = validate(
        @_,
        {
          repo => {
            type => SCALAR
          }
        }
      );

      return File::Spec->rel2abs( $self->config->{RepositoryRoot}
          . "/head/"
          . $self->config->{Repository}->{ $option{repo} }->{local} );
    },
  );

  my $r = $self->routes;
  $r->get('/')->to('index#index');
  $r->get('/v1/_ping')->to('index#ping');
  $r->get('/v1/search')->to('search#search');

  my $auth_repo_lib = $r->bridge('/v1/repositories/:name')->to('auth#login', repo_namespace => 'library');
  $auth_repo_lib->get('/images')->to('repository#get_repo_images');
  $auth_repo_lib->get('/tags')->to('repository#get_repo_tag');
  $auth_repo_lib->put('/tags/:tag')->to('repository#put_repo_tag');
  $auth_repo_lib->put('/images')->to('repository#put_repo_image');
  $auth_repo_lib->put('/')->to('repository#put_repo');

  my $auth_repo = $r->bridge('/v1/repositories/:repo_namespace/:name')->to('auth#login');
  $auth_repo->get('/images')->to('repository#get_repo_images');
  $auth_repo->get('/tags')->to('repository#get_repo_tag');
  $auth_repo->put('/tags/:tag')->to('repository#put_repo_tag');
  $auth_repo->put('/images')->to('repository#put_repo_image');
  $auth_repo->put('/')->to('repository#put_repo');

  my $auth_image = $r->bridge('/v1/images/:name')->to('auth#login', repo_namespace => 'images');
  $auth_image->get('/json')->to('image#get_image');
  $auth_image->get('/ancestry')->to('image#get_image_ancestry');
  $auth_image->get('/layer')->to('image#get_image_layer');
  $auth_image->put('/json')->to('image#put_image');
  $auth_image->put('/layer')->to('image#put_image_layer');
  $auth_image->put('/checksum')->to('image#put_image_checksum');
}

1;
