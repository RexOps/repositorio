#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:
   
package Rex::Repositorio::Server::Helper::Common;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Plugin';
use Params::Validate qw(:all);
use File::Spec;
use JSON::XS;

sub register {
  my ( $self, $app ) = @_;

  $app->helper(
    config => sub {
      my $config = decode_json( $ENV{REPO_CONFIG} );
      return $config;
    },
  );

  $app->helper(
    repo => sub {
      my $self = shift;
      return {
        %{ $self->config->{Repository}->{ $ENV{REPO_NAME} } },
        name => $ENV{REPO_NAME}
      };
    },
  );

  $app->helper(
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
}

1;
