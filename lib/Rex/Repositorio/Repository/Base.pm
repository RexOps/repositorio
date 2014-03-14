#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Base;

use Moose;
use Try::Tiny;
use common::sense;
use Carp;

has app  => ( is => 'ro' );
has repo => ( is => 'ro' );


1;
