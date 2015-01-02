#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository_Factory;

use common::sense;
use Params::Validate qw(:all);
use English;
use Carp;

sub create {
  my $class  = shift;
  my %option = validate(
    @_,
    {
      type => {
        type => SCALAR
      },
      options => {
        type => HASHREF
      }
    }
  );

  my $type     = $option{type};
  my $repo_mod = "Rex::Repositorio::Repository::$type";
  eval "use $repo_mod;";
  if ($EVAL_ERROR) {
    confess "Error loading repository type: $type. ($EVAL_ERROR)";
  }

  return $repo_mod->new( %{ $option{options} } );
}

1;
